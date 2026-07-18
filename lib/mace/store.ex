defmodule Mace.Store do
  @moduledoc false

  @registry __MODULE__
  @neg_cache :mace_neg_cache
  @neg_keys :mace_neg_keys

  @doc false
  def init do
    res =
      case Registry.start_link(keys: :unique, name: @registry) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

    create_cache_tables()
    res
  end

  def put(pid, app, key, value) when is_atom(app) and is_atom(key) do
    updater = fn current ->
      app_map = Map.get(current, app, %{})
      Map.put(current, app, Map.put(app_map, key, value))
    end

    case Registry.update_value(@registry, pid, updater) do
      {_, _} -> :ok
      :error ->
        config = updater.(%{})
        {:ok, _} = Registry.register(@registry, pid, config)
    end

    invalidate_cache(app, key)
    :ok
  end

  @doc """
  Stores a config override for the current process.
  """
  def put(app, key, value) when is_atom(app) and is_atom(key) do
    put(self(), app, key, value)
  end

  def put(app, kvlist) do
    kvlist
    |> Keyword.new()
    |> Enum.map(fn {k, v} -> put(self(), app, k, v) end)
  rescue
    Protocol.UndefinedError ->
      raise ArgumentError, "expected a keyword list, got: #{inspect(kvlist)}"
  end

  @doc """
  Fetches a config override for the given pid.
  Returns `{:ok, value}` or `:error`.

  A key explicitly deleted with `delete/3` returns `{:ok, nil}`, not `:error`,
  mirroring `Application.get_env` after `Application.delete_env`.

  If the pid has no registered config, walks monitored processes
  to find an ancestor that does, enabling spawned Tasks and GenServers to
  inherit test config automatically.
  """
  def fetch(pid, app, key) when is_pid(pid) and is_atom(app) and is_atom(key) do
    if :ets.member(@neg_cache, {pid, app, key}) do
      :error
    else
      do_fetch(pid, app, key)
    end
  end

  defp do_fetch(pid, app, key) do
    config_pid = pid_with_config(pid)

    if config_pid do
      config_map = to_map_direct(config_pid)

      result =
        case get_in(config_map, [app, key]) do
          nil -> :error
          {__MODULE__, :tombstone} -> {:ok, nil}
          value -> {:ok, value}
        end

      case {config_pid, result} do
        {^pid, {:ok, _value}} ->
          :ok

        {_pid, {:ok, _value}} ->
          :ets.delete(@neg_cache, {pid, app, key})

        {_, :error} ->
          cache_miss(pid, app, key)
      end

      result
    else
      cache_miss(pid, app, key)
      :error
    end
  end

  @doc """
  Removes all config overrides for the given pid.
  """
  def delete(pid) when is_pid(pid) do
    Registry.unregister(@registry, pid)

    flush_cache()
  end

  @doc """
  Removes a specific config override for the given pid.

  Mirrors `Application.delete_env/2`: sets the key to `nil` so that
  `fetch` returns `{:ok, nil}` and the tree walk stops at this pid.

  ## Examples

      iex> Mace.Store.put(self(), :my_app, :timeout, 100)
      iex> Mace.Store.delete(self(), :my_app, :timeout)
      :ok
      iex> Mace.Store.fetch(self(), :my_app, :timeout)
      {:ok, nil}
  """
  def delete(pid, app, key) when is_pid(pid) and is_atom(app) and is_atom(key) do
    put(pid, app, key, {__MODULE__, :tombstone})
  end

  @doc """
  Removes a specific config override for the current process.
  """
  def delete(app, key) when is_atom(app) and is_atom(key) do
    delete(self(), app, key)
  end

  @doc """
  Returns all overrides for the given pid as a nested map:
  %{app => %{key => value}}

  Walks linked processes if the pid has no registered config.
  """
  def to_map(pid) when is_pid(pid) do
    pid
    |> then(&(pid_with_config(&1) || &1))
    |> to_map_direct()
    |> unwrap_tombstones()
  end

  @doc false
  def to_map_direct(pid) when is_pid(pid) do
    case Registry.lookup(@registry, pid) do
      [{_pid, config}] -> config
      [] -> %{}
    end
  end

  @doc """
  Loads a config map (as produced by to_map/1) into the current pid's store.
  Used by spawn helpers to transfer config to child processes.
  """
  def load(map) when map_size(map) > 0 do
    register(self(), map)

    for {app, app_map} <- map, {key, _value} <- app_map do
      invalidate_cache(app, key)
    end

    :ok
  end

  def load(empty) when is_map(empty), do: :ok

  defp unwrap_tombstones(%{} = config) do
    Map.new(config, fn {app, app_map} ->
      {app, Map.new(app_map, fn {key, value} -> {key, unwrap_tombstone(value)} end)}
    end)
  end

  defp unwrap_tombstone({__MODULE__, :tombstone}), do: nil
  defp unwrap_tombstone(value), do: value

  defp register(key, config) when is_pid(key) do
    :ok = Registry.unregister(@registry, key)
    {:ok, _} = Registry.register(@registry, key, config)
    :ok
  end

  defp pid_with_config(pid) when is_pid(pid) do
    find_in_tree([{pid, :links}], MapSet.new())
  end

  defp find_in_tree([], _seen), do: nil

  defp find_in_tree([{pid, source} | rest], seen) do
    if MapSet.member?(seen, pid) do
      find_in_tree(rest, seen)
    else
      case Registry.lookup(@registry, pid) do
        [{_pid, _config}] ->
          pid

        [] ->
          candidates = candidate_pids(pid, source)
          find_in_tree(rest ++ candidates, MapSet.put(seen, pid))
      end
    end
  end

  defp candidate_pids(pid, source) when is_pid(pid) do
    {links, monitored} = get_process_relations(pid)
    registry_pid = Process.whereis(@registry)

    pids =
      case source do
        :links ->
          tag_candidates(links, :links, registry_pid) ++
            tag_candidates(monitored, :monitored_by, registry_pid)

        :monitored_by ->
          tag_candidates(monitored, :monitored_by, registry_pid)
      end

    Enum.filter(pids, fn {p, _} -> p != nil end)
  end

  defp tag_candidates(pids, tag, registry_pid) do
    for pid <- pids, is_pid(pid), pid != registry_pid, do: {pid, tag}
  end

  defp get_process_relations(pid) do
    case Process.info(pid, [:links, :monitored_by]) do
      info when is_list(info) ->
        {Keyword.get(info, :links, []), Keyword.get(info, :monitored_by, [])}
      _ ->
        {[], []}
    end
  rescue
    _ -> {[], []}
  end

  # -- negative cache --------------------------------------------------------

  defp create_cache_tables do
    try do
      :ets.new(@neg_cache, [:set, :public, :named_table])
    rescue
      ArgumentError -> :ok
    end

    try do
      :ets.new(@neg_keys, [:bag, :public, :named_table])
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  defp cache_miss(pid, app, key) do
    :ets.insert(@neg_cache, {{pid, app, key}, true})
    :ets.insert(@neg_keys, {{app, key}, pid})
    :ok
  end

  defp invalidate_cache(app, key) do
    for pid <- :ets.lookup(@neg_keys, {app, key}) do
      :ets.delete(@neg_cache, {elem(pid, 1), app, key})
    end

    :ets.delete(@neg_keys, {app, key})
  end

  defp flush_cache do
    :ets.delete_all_objects(@neg_cache)
    :ets.delete_all_objects(@neg_keys)
  end
end

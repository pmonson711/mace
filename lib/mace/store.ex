defmodule Mace.Store do
  @moduledoc false

  @config_table :mace_config
  @neg_cache :mace_neg_cache
  @neg_keys :mace_neg_keys
  @neg_deps :mace_neg_deps
  @mon_ets  :mace_mon

  @doc false
  def init do
    create_table(@config_table, :set)
    create_cache_tables()
    start_cache_monitor()
    :ok
  end

  defp create_table(name, type) do
    try do
      :ets.new(name, [type, :public, :named_table])
    rescue
      ArgumentError -> :ok
    end
  end

  def put(pid, app, key, value) when is_atom(app) and is_atom(key) do
    current =
      case :ets.lookup(@config_table, pid) do
        [{^pid, config}] -> config
        [] -> %{}
      end

    app_map = Map.get(current, app, %{})
    new_config = Map.put(current, app, Map.put(app_map, key, value))

    :ets.insert(@config_table, {pid, new_config})
    monitor_config(pid)
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

  @doc """
  Same as `fetch/3` but logs the full tree walk path to stderr.
  Shows every PID visited, whether it had config, and where the walk stopped.
  """
  def debug_fetch(pid, app, key) when is_pid(pid) and is_atom(app) and is_atom(key) do
    result = debug_fetch_walk([{pid, :links2}], MapSet.new(), pid, app, key)
    label = "Mace.debug_fetch(#{inspect(pid)}, #{inspect(app)}, #{inspect(key)})"
    IO.puts(:stderr, "#{label} => #{inspect(result)}")
    result
  end

  defp debug_fetch_walk([], _seen, _query_pid, _app, _key) do
    IO.puts(:stderr, "  tree exhausted — no config found")
    :error
  end

  defp debug_fetch_walk([{pid, source} | rest], seen, query_pid, app, key) do
    if MapSet.member?(seen, pid) do
      debug_fetch_walk(rest, seen, query_pid, app, key)
    else
      case lookup_config(pid) do
        :none ->
          IO.puts(:stderr, "  visit #{inspect(pid)}  src=#{source}  no config, expanding...")
          candidates = candidate_pids(pid, source)
          debug_fetch_walk(rest ++ candidates, MapSet.put(seen, pid), query_pid, app, key)

        config_map ->
          case get_in(config_map, [app, key]) do
            nil ->
              keys = config_map |> Map.keys() |> Enum.map_join(", ", &inspect/1)
              IO.puts(:stderr, "  visit #{inspect(pid)}  src=#{source}  has config apps=[#{keys}]  miss for #{inspect(key)}, continuing...")
              candidates = candidate_pids(pid, source)
              debug_fetch_walk(rest ++ candidates, MapSet.put(seen, pid), query_pid, app, key)

            {__MODULE__, :tombstone} ->
              IO.puts(:stderr, "  visit #{inspect(pid)}  src=#{source}  FOUND tombstone => {:ok, nil}")

              if pid != query_pid do
                :ets.delete(@neg_cache, {query_pid, app, key})
              end

              {:ok, nil}

            value ->
              IO.puts(:stderr, "  visit #{inspect(pid)}  src=#{source}  FOUND #{inspect(value)} => {:ok, #{inspect(value)}}")

              if pid != query_pid do
                :ets.delete(@neg_cache, {query_pid, app, key})
              end

              {:ok, value}
          end
      end
    end
  end

  defp do_fetch(pid, app, key) do
    find_in_tree_with_key([{pid, :links2}], MapSet.new(), pid, app, key)
  end

  defp find_in_tree_with_key([], _seen, query_pid, app, key) do
    cache_miss(query_pid, app, key)
    :error
  end

  defp find_in_tree_with_key([{pid, source} | rest], seen, query_pid, app, key) do
    if MapSet.member?(seen, pid) do
      find_in_tree_with_key(rest, seen, query_pid, app, key)
    else
      case lookup_config(pid) do
        :none ->
          candidates = candidate_pids(pid, source)
          find_in_tree_with_key(rest ++ candidates, MapSet.put(seen, pid), query_pid, app, key)

        config_map ->
          case get_in(config_map, [app, key]) do
            nil ->
              candidates = candidate_pids(pid, source)
              find_in_tree_with_key(rest ++ candidates, MapSet.put(seen, pid), query_pid, app, key)

            {__MODULE__, :tombstone} ->
              if pid != query_pid do
                :ets.delete(@neg_cache, {query_pid, app, key})
              end

              {:ok, nil}

            value ->
              if pid != query_pid do
                :ets.delete(@neg_cache, {query_pid, app, key})
              end

              {:ok, value}
          end
      end
    end
  end

  defp lookup_config(pid) do
    case :ets.lookup(@config_table, pid) do
      [{^pid, config}] -> config
      [] -> :none
    end
  end

  @doc """
  Removes all config overrides for the given pid.
  """
  def delete(pid) when is_pid(pid) do
    :ets.delete(@config_table, pid)
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
    case lookup_config(pid) do
      :none -> %{}
      config -> config
    end
  end

  @doc """
  Loads a config map (as produced by to_map/1) into the current pid's store.
  Used by spawn helpers to transfer config to child processes.
  """
  def load(map) when map_size(map) > 0 do
    register_cfg(self(), map)

    for {app, app_map} <- map, {key, _value} <- app_map do
      invalidate_cache(app, key)
    end

    monitor_config(self())
    :ok
  end

  def load(empty) when is_map(empty), do: :ok

  defp register_cfg(pid, config) when is_pid(pid) do
    :ets.insert(@config_table, {pid, config})
  end

  defp unwrap_tombstones(%{} = config) do
    Map.new(config, fn {app, app_map} ->
      {app, Map.new(app_map, fn {key, value} -> {key, unwrap_tombstone(value)} end)}
    end)
  end

  defp unwrap_tombstone({__MODULE__, :tombstone}), do: nil
  defp unwrap_tombstone(value), do: value

  defp pid_with_config(pid) when is_pid(pid) do
    find_in_tree([{pid, :links2}], MapSet.new())
  end

  defp find_in_tree([], _seen), do: nil

  defp find_in_tree([{pid, source} | rest], seen) do
    if MapSet.member?(seen, pid) do
      find_in_tree(rest, seen)
    else
      case lookup_config(pid) do
        :none ->
          candidates = candidate_pids(pid, source)
          find_in_tree(rest ++ candidates, MapSet.put(seen, pid))

        _config_map ->
          pid
      end
    end
  end

  defp candidate_pids(pid, source) when is_pid(pid) do
    {links, monitored} = get_process_relations(pid)

    pids =
      case source do
        :links2 ->
          tag_candidates(links, :links) ++
            tag_candidates(monitored, :monitored_by)

        :links ->
          tag_candidates(links, :monitored_by) ++
            tag_candidates(monitored, :monitored_by)

        :monitored_by ->
          tag_candidates(monitored, :monitored_by)
      end

    Enum.filter(pids, fn {p, _} -> p != nil end)
  end

  defp tag_candidates(pids, tag) do
    for pid <- pids, is_pid(pid), do: {pid, tag}
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
    create_table(@neg_cache, :set)
    create_table(@neg_keys, :bag)
    create_table(@neg_deps, :bag)
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

  # -- cache monitor ----------------------------------------------------------

  defp start_cache_monitor do
    create_table(@mon_ets, :set)

    case :ets.lookup(@mon_ets, :pid) do
      [{:pid, pid}] when is_pid(pid) ->
        case Process.alive?(pid) do
          true -> :ok
          false -> respawn_monitor()
        end

      _ ->
        respawn_monitor()
    end
  end

  defp respawn_monitor do
    pid =
      spawn(fn ->
        down_handler()
      end)

    :ets.insert(@mon_ets, {:pid, pid})
  end

  defp monitor_config(config_pid) when is_pid(config_pid) do
    case :ets.lookup(@mon_ets, :pid) do
      [{:pid, mon_pid}] ->
        unless :ets.member(@mon_ets, {:m, config_pid}) do
          :ets.insert(@mon_ets, {{:m, config_pid}, true})
          send(mon_pid, {:monitor, config_pid})
        end

      _ ->
        :ok
    end
  end

  defp down_handler do
    receive do
      {:monitor, pid} ->
        Process.monitor(pid)
        down_handler()

      {:DOWN, _ref, :process, pid, _reason} ->
        :ets.delete(@config_table, pid)
        :ets.delete(@mon_ets, {:m, pid})
        flush_cache()
        down_handler()
    end
  end
end

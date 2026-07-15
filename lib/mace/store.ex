defmodule Mace.Store do
  @moduledoc false

  @registry __MODULE__

  @doc false
  def init do
    case Registry.start_link(keys: :unique, name: @registry) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @doc """
  Stores a config override for the current process.
  """
  def put(app, key, value) when is_atom(app) and is_atom(key) do
    current = to_map_direct(self())
    app_map = Map.get(current, app, %{})
    updated = Map.put(current, app, Map.put(app_map, key, value))
    register(self(), updated)
  end

  def put(app, kvlist) do
    kvlist
    |> Keyword.new()
    |> Enum.map(fn {k, v} -> put(app, k, v) end)
  rescue
    Protocol.UndefinedError ->
      raise ArgumentError, "expected a keyword list, got: #{inspect(kvlist)}"
  end

  @doc """
  Fetches a config override for the given pid.
  Returns `{:ok, value}` or `:error`.

  If the pid has no registered config, walks linked and monitored processes
  to find an ancestor that does, enabling spawned Tasks and GenServers to
  inherit test config automatically.
  """
  def fetch(pid, app, key) when is_pid(pid) and is_atom(app) and is_atom(key) do
    config_pid = pid_with_config(pid)

    if config_pid do
      case get_in(to_map_direct(config_pid), [app, key]) do
        nil -> :error
        value -> {:ok, value}
      end
    else
      :error
    end
  end

  @doc """
  Removes all config overrides for the given pid.
  """
  def delete(pid) when is_pid(pid) do
    Registry.unregister(@registry, pid)
  end

  @doc """
  Returns all overrides for the given pid as a nested map:
  %{app => %{key => value}}

  Walks linked processes if the pid has no registered config.
  """
  def to_map(pid) when is_pid(pid) do
    to_map_direct(pid_with_config(pid) || pid)
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
  end

  def load(empty) when is_map(empty), do: :ok

  defp register(key, config) when is_pid(key) do
    :ok = Registry.unregister(@registry, key)
    {:ok, _} = Registry.register(@registry, key, config)
    :ok
  end

  defp pid_with_config(pid) when is_pid(pid) do
    case Registry.lookup(@registry, pid) do
      [{^pid, _config}] -> pid
      [] -> find_in_candidates(candidate_pids(pid))
    end
  end

  defp find_in_candidates([]), do: nil

  defp find_in_candidates([candidate | rest]) do
    case Registry.lookup(@registry, candidate) do
      [{^candidate, _config}] -> candidate
      [] -> find_in_candidates(rest)
    end
  end

  defp candidate_pids(pid) when is_pid(pid) do
    links = safe_process_info(pid, :links) || []
    monitored_by = safe_process_info(pid, :monitored_by) || []
    links ++ monitored_by
  end

  defp safe_process_info(pid, key) do
    case Process.info(pid, key) do
      {^key, value} when is_list(value) -> value
      _ -> []
    end
  rescue
    _ -> []
  end
end

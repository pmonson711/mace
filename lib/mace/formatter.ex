defmodule Mace.Formatter do
  @moduledoc """
  Stores config diffs for display on test failure.

  Used internally by `Mace.cleanup/1` in `on_exit` callbacks.
  The diff data is read by an ExUnit formatter (registered separately)
  that injects diffs into test failure output.

  ## Usage in tests

      setup context do
        Mace.set(:my_app, :timeout, 100)
        on_exit(fn -> Mace.cleanup(context) end)
        :ok
      end

  The `cleanup/1` call records the current process's config diffs
  (keyed by the test's module and name) and then resets the config.
  On test failure, the formatter reads and displays the diff.
  """

  @doc false
  def reset do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  rescue
    _ ->
      Agent.update(__MODULE__, fn _ -> %{} end)
  end

  @doc """
  Records the current process's config diffs for the given test.
  Called by `Mace.cleanup/1`.
  """
  def record(module, test_name) do
    pid = self()
    configs = Mace.Store.to_map(pid)

    diffs =
      Enum.reduce(configs, "", fn {app, overrides}, acc ->
        snapshot = Mace.Diff.snapshot(app)
        diff_map = Mace.Diff.compute(snapshot, overrides || %{})

        case Mace.Diff.format(app, diff_map) do
          "" -> acc
          formatted -> acc <> formatted
        end
      end)

    Agent.update(__MODULE__, fn state -> Map.put(state, {module, test_name}, diffs) end)
  end

  @doc """
  Returns the recorded diff for a given test.
  """
  def lookup(module, test_name) do
    Agent.get(__MODULE__, fn state -> Map.get(state, {module, test_name}, "") end)
  end

  @doc """
  Clears the recorded diff for a given test.
  """
  def clear(module, test_name) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, {module, test_name}) end)
  end
end

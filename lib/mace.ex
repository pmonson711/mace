defmodule Mace do
  @moduledoc """
  Per-test configuration isolation for ExUnit.

  Provides `set/3`, `set_many/2`, `get/3`, `reset/0`, and `diff/1` to manage
  test-scoped application config that intercepts `Application.get_env` transparently.

  ## Setup

  In `test/test_helper.exs`:

      Mace.Store.init()
      ExUnit.start()

  Modules that need `Application.get_env` interception must also call
  `Mace.Mock.install()` in a `setup_all` block.

  In your test module:

      defmodule MyTest do
        use ExUnit.Case, async: true

        setup do
          Mace.set(:my_app, :timeout, 100)
          on_exit(fn -> Mace.reset() end)
          :ok
        end

        test "uses overridden timeout" do
          # Application.get_env(:my_app, :timeout) => 100
          assert MyModule.do_thing() == :ok
        end
      end
  """

  @doc """
  Sets a config override for the current test process.

  Subsequent calls to `Application.get_env(app, key)` from the same process
  will return `value` instead of the real application config.
  """
  defdelegate set(app, key, value), to: Mace.Store, as: :put

  @doc """
  Sets multiple config overrides from a keyword list.

  ## Example

      Mace.set(:my_app, timeout: 100, debug: true)
  """
  defdelegate set(app, kvlist), to: Mace.Store, as: :put

  @doc """
  Gets the active config override for the current process.
  Returns `{:ok, value}` or `:error`.
  """
  def get(app, key) do
    Mace.Store.fetch(self(), app, key)
  end

  @doc """
  Clears all config overrides for the current test process.
  Call in `on_exit` to prevent config bleed.
  """
  def reset do
    Mace.Store.delete(self())
    :ok
  end

  @doc """
  Returns a formatted diff string comparing the current process's config
  overrides against the application defaults.

  Returns empty string if no overrides or all overrides match defaults.
  """
  def diff(app) do
    snapshot = Mace.Diff.snapshot(app)

    overrides =
      Mace.Store.to_map(self())
      |> Map.get(app, %{})

    diff_map = Mace.Diff.compute(snapshot, overrides)
    Mace.Diff.format(app, diff_map)
  end

  @doc """
  Spawns a Task that inherits the current process's config overrides.
  Use instead of `Task.async/1` when the spawned code calls `Application.get_env`.

  ## Example

      task = Mace.task(fn -> MyModule.do_async_work() end)
      result = Task.await(task)
  """
  def task(fun) do
    Mace.Spawn.task(fun)
  end

  @doc """
  Returns the current pid's full config overrides as a nested map.
  Useful for debugging and for manual config transfer to spawned processes.

  ## Example

      config = Mace.pid_config()
      # => %{my_app: %{timeout: 100, debug: true}}
  """
  def pid_config do
    Mace.Store.to_map(self())
  end

  @doc """
  Records the current process's config diffs and then resets.
  Call this in `on_exit` to enable automatic config-diff display on test failure.

  ## Example

      setup context do
        Mace.set(:my_app, :timeout, 100)
        on_exit(fn -> Mace.cleanup(context) end)
        :ok
      end
  """
  def cleanup(context) do
    module = Map.get(context, :module)
    test_name = Map.get(context, :test)
    Mace.Formatter.record(module, test_name)
    reset()
  end
end

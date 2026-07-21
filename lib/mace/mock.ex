defmodule Mace.Mock do
  @moduledoc false

  @doc """
  Installs the :meck mock on the Application module.
  Must be called before tests use Mace.
  Should be called once in test_helper.exs.
  Returns :ok if already installed.
  Safe to call concurrently — :global lock serializes installers.
  """
  def install do
    lock_id = {:mace_mock_install, self()}
    :global.set_lock(lock_id)

    try do
      if installed?() do
        :ok
      else
        :meck.new(Application, [:passthrough, :non_strict])

        :meck.expect(Application, :get_env, 2, fn app, key ->
          case Mace.Store.fetch(self(), app, key) do
            {:ok, value} -> value
            :error -> :meck.passthrough([app, key])
          end
        end)

        :meck.expect(Application, :get_env, 3, fn app, key, default ->
          case Mace.Store.fetch(self(), app, key) do
            {:ok, value} -> value
            :error -> :meck.passthrough([app, key, default])
          end
        end)

        :meck.expect(Application, :get_all_env, 1, fn app ->
          real = :meck.passthrough([app])
          overrides = Mace.Store.to_map(self()) |> Map.get(app, %{})

          Enum.reduce(overrides, real, fn {key, value}, acc ->
            Keyword.put(acc, key, value)
          end)
        end)

        :meck.expect(Application, :fetch_env, 2, fn app, key ->
          case Mace.Store.fetch(self(), app, key) do
            {:ok, value} -> {:ok, value}
            :error -> :meck.passthrough([app, key])
          end
        end)

        :meck.expect(Application, :fetch_env!, 2, fn app, key ->
          case Mace.Store.fetch(self(), app, key) do
            {:ok, value} -> value
            :error -> :meck.passthrough([app, key])
          end
        end)

        :ok
      end
    after
      :global.del_lock(lock_id)
    end
  end

  @doc """
  Uninstalls the :meck mock on the Application module.
  """
  def uninstall do
    lock_id = {:mace_mock_uninstall, self()}

    :global.set_lock(lock_id)

    try do
      if installed?() do
        :meck.unload(Application)
      end

      :ok
    after
      :global.del_lock(lock_id)
    end
  end

  defp installed? do
    :meck.history(Application) != false
  rescue
    _ -> false
  end
end

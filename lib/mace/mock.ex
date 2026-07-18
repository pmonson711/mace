defmodule Mace.Mock do
  @moduledoc false

  @doc """
  Installs the :meck mock on the Application module.
  Must be called before tests use Mace.
  Should be called once in test_helper.exs.
  Returns :ok if already installed.
  """
  def install do
    if installed?() do
      :ok
    else
      try do
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
      rescue
        e in ErlangError ->
          case e.original do
            {:already_started, _pid} -> :ok
            _ -> reraise e, __STACKTRACE__
          end
      end

      :ok
    end
  end

  @doc """
  Uninstalls the :meck mock on the Application module.
  """
  def uninstall do
    if installed?() do
      :meck.unload(Application)
    end

    :ok
  end

  defp installed? do
    :meck.history(Application) != false
  rescue
    _ -> false
  end
end

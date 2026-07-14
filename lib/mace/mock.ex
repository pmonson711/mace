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
      :ok = :meck.new(Application, [:passthrough, :non_strict])

      :meck.expect(Application, :get_env, 2, fn app, key ->
        case Mace.Store.fetch(self(), app, key) do
          {:ok, value} -> value
          :error -> fallback_get_env(app, key)
        end
      end)

      :meck.expect(Application, :get_env, 3, fn app, key, default ->
        case Mace.Store.fetch(self(), app, key) do
          {:ok, value} -> value
          :error -> fallback_get_env(app, key, default)
        end
      end)

      :meck.expect(Application, :get_all_env, 1, fn app ->
        real = fallback_get_all_env(app)
        overrides = Mace.Store.to_map(self()) |> Map.get(app, %{})

        Enum.reduce(overrides, real, fn {key, value}, acc ->
          Keyword.put(acc, key, value)
        end)
      end)

      :meck.expect(Application, :fetch_env, 2, fn app, key ->
        case Mace.Store.fetch(self(), app, key) do
          {:ok, value} -> {:ok, value}
          :error -> fallback_fetch_env(app, key)
        end
      end)

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

  # Calls to :application module bypass the mocked Elixir.Application

  defp fallback_get_env(app, key) do
    case :application.get_env(app, key) do
      {:ok, value} -> value
      :undefined -> nil
    end
  end

  defp fallback_get_env(app, key, default) do
    case :application.get_env(app, key) do
      {:ok, value} -> value
      :undefined -> default
    end
  end

  defp fallback_get_all_env(app) do
    case :application.get_all_env(app) do
      {:ok, env} -> env
      _ -> []
    end
  end

  defp fallback_fetch_env(app, key) do
    case :application.get_env(app, key) do
      {:ok, value} -> {:ok, value}
      :undefined -> :error
    end
  end
end

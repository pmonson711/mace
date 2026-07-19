defmodule Mace.Mock do
  @moduledoc false

  @doc """
  Installs the :meck mock on the Application module (and optionally System).
  Must be called before tests use Mace.
  Should be called once in test_helper.exs.
  Returns :ok if already installed.

  ## Options

  * `:system_env` — when true, also mocks `System.get_env/0`,
    `System.get_env/1`, `System.get_env/2`, `System.put_env/1`,
    `System.put_env/2`, and `System.delete_env/1`.
  """
  def install(opts \\ []) do
    system_env? = Keyword.get(opts, :system_env, false)

    if app_installed?() do
      :ok
    else
      install_app_mock()
    end

    if system_env? and not system_installed?() do
      install_system_mock()
    end

    :ok
  end

  @doc """
  Uninstalls :meck mocks on Application and System modules.
  """
  def uninstall do
    if app_installed?(), do: :meck.unload(Application)

    try do
      if system_installed?(), do: :meck.unload(System)
    rescue
      _ -> :ok
    end

    :ok
  end

  defp install_app_mock do
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

  defp install_system_mock do
    try do
      :meck.new(System, [:passthrough, :non_strict])

      :meck.expect(System, :get_env, 0, fn ->
        real = :meck.passthrough([])

        if Process.get(:mace_system_env_intercept) do
          overrides = Mace.Store.to_map(self()) |> Map.get(:system_env, %{})
          Map.merge(real, overrides)
        else
          real
        end
      end)

      :meck.expect(System, :get_env, 1, fn key ->
        if Process.get(:mace_system_env_intercept) do
          case Mace.Store.fetch(self(), :system_env, key) do
            {:ok, value} -> value
            :error -> :meck.passthrough([key])
          end
        else
          :meck.passthrough([key])
        end
      end)

      :meck.expect(System, :get_env, 2, fn key, default ->
        if Process.get(:mace_system_env_intercept) do
          case Mace.Store.fetch(self(), :system_env, key) do
            {:ok, value} -> value
            :error -> :meck.passthrough([key, default])
          end
        else
          :meck.passthrough([key, default])
        end
      end)

      :meck.expect(System, :put_env, 1, fn env_map ->
        if Process.get(:mace_system_env_intercept) do
          Enum.each(env_map, fn {key, value} ->
            Mace.Store.put(self(), :system_env, key, value)
          end)

          :ok
        else
          :meck.passthrough([env_map])
        end
      end)

      :meck.expect(System, :put_env, 2, fn key, value ->
        if Process.get(:mace_system_env_intercept) do
          Mace.Store.put(self(), :system_env, key, value)
          :ok
        else
          :meck.passthrough([key, value])
        end
      end)

      :meck.expect(System, :delete_env, 1, fn key ->
        if Process.get(:mace_system_env_intercept) do
          Mace.Store.delete(self(), :system_env, key)
          :ok
        else
          :meck.passthrough([key])
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

  defp app_installed? do
    :meck.history(Application) != false
  rescue
    _ -> false
  end

  defp system_installed? do
    :meck.history(System) != false
  rescue
    _ -> false
  end
end

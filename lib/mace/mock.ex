defmodule Mace.Mock do
  @moduledoc false

  @doc """
  Installs the :meck mock on the Application module.
  Must be called before tests use Mace.
  Should be called once in test_helper.exs.
  Returns :ok if already installed.

  ## Options

    * `:put_env` - mock `Application.get_env` and friends (default `false`)
    * `:persistent_term` - mock `:persistent_term.get/put/erase` (default `false`)
  """
  def install(opts \\ []) do
    put_env? = Keyword.get(opts, :put_env, false)
    persistent_term? = Keyword.get(opts, :persistent_term, false)

    if put_env? do
      install_app_mock()
    end

    if persistent_term? do
      install_persistent_term_mock()
    end

    :ok
  end

  @doc """
  Uninstalls all :meck mocks.
  """
  def uninstall do
    if app_installed?() do
      :meck.unload(Application)
    end

    if persistent_term_installed?() do
      :meck.unload(:persistent_term)
    end

    :ok
  end

  # -- Application mock --------------------------------------------------------

  defp install_app_mock do
    if app_installed?() do
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

  defp app_installed? do
    :meck.history(Application) != false
  rescue
    _ -> false
  end

  # -- :persistent_term mock ---------------------------------------------------

  defp install_persistent_term_mock do
    if persistent_term_installed?() do
      :ok
    else
      try do
        :meck.new(:persistent_term, [:passthrough, :non_strict])

        :meck.expect(:persistent_term, :get, 1, fn key ->
          if Process.get(:mace_persistent_term_intercept) do
            case Mace.Store.fetch(self(), :persistent_term, key) do
              {:ok, value} when not is_nil(value) -> value
              _ -> :meck.passthrough([key])
            end
          else
            :meck.passthrough([key])
          end
        end)

        :meck.expect(:persistent_term, :get, 2, fn key, default ->
          if Process.get(:mace_persistent_term_intercept) do
            case Mace.Store.fetch(self(), :persistent_term, key) do
              {:ok, value} when not is_nil(value) -> value
              _ -> :meck.passthrough([key, default])
            end
          else
            :meck.passthrough([key, default])
          end
        end)

        :meck.expect(:persistent_term, :put, 2, fn key, value ->
          if Process.get(:mace_persistent_term_intercept) do
            Mace.Store.put(self(), :persistent_term, key, value)
            :ok
          else
            :meck.passthrough([key, value])
          end
        end)

        :meck.expect(:persistent_term, :erase, 1, fn key ->
          if Process.get(:mace_persistent_term_intercept) do
            Mace.Store.delete(self(), :persistent_term, key)
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
  end

  defp persistent_term_installed? do
    :meck.history(:persistent_term) != false
  rescue
    _ -> false
  end
end

defmodule Mace.Mock do
  @moduledoc false

  @doc """
  Installs the :meck mock on the Application module.
  Must be called before tests use Mace.
  Should be called once in test_helper.exs.

  ## Options

    * `:put_env` — when `true`, also intercepts `Application.put_env/3`,
      `Application.put_all_env/2`, and `Application.delete_env/2`. Writes go to
      the per-process `Mace.Store` instead of the global application env, gated
      by a process-level flag.

  Returns :ok if already installed.
  """
  def install(opts \\ []) do
    put_env? = Keyword.get(opts, :put_env, false)

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

        if put_env? do
          :meck.expect(Application, :put_env, 3, fn app, key, value ->
            if Process.get(:mace_put_env_intercept) do
              Mace.Store.put(self(), app, key, value)
              :ok
            else
              :meck.passthrough([app, key, value])
            end
          end)

          :meck.expect(Application, :put_all_env, 2, fn app, kvlist ->
            if Process.get(:mace_put_env_intercept) do
              Enum.each(kvlist, fn {key, value} ->
                Mace.Store.put(self(), app, key, value)
              end)
              :ok
            else
              :meck.passthrough([app, kvlist])
            end
          end)

          :meck.expect(Application, :delete_env, 2, fn app, key ->
            if Process.get(:mace_put_env_intercept) do
              Mace.Store.delete(self(), app, key)
              :ok
            else
              :meck.passthrough([app, key])
            end
          end)
        end
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

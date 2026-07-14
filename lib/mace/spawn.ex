defmodule Mace.Spawn do
  @moduledoc false

  @doc """
  Spawns a Task that inherits the parent process's config overrides.
  Returns a Task struct (same as Task.async/1).
  """
  def task(fun) do
    parent_config = Mace.Store.to_map(self())

    Task.async(fn ->
      Mace.Store.load(parent_config)
      fun.()
    end)
  end
end

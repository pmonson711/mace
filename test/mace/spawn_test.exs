defmodule Mace.SpawnTest do
  use ExUnit.Case, async: true

  setup do
    Mace.Store.init()
    Mace.put_config(:my_app, :timeout, 100)
    on_exit(fn -> Mace.reset() end)
    :ok
  end

  describe "task/1" do
    test "spawns a task that inherits parent's config via load" do
      task =
        Mace.task(fn ->
          Mace.get_config(:my_app, :timeout)
        end)

      assert Task.await(task) == {:ok, 100}
    end

    test "linked Task.async inherits config automatically via link walk" do
      task =
        Task.async(fn ->
          Mace.Store.fetch(self(), :my_app, :timeout)
        end)

      assert Task.await(task) == {:ok, 100}
    end

    test "returns the function's result" do
      task = Mace.task(fn -> 42 end)
      assert Task.await(task) == 42
    end

    test "child modifying config does not affect parent" do
      task =
        Mace.task(fn ->
          Mace.put_config(:my_app, :timeout, 999)
          Mace.get_config(:my_app, :timeout)
        end)

      assert Task.await(task) == {:ok, 999}
      assert Mace.get_config(:my_app, :timeout) == {:ok, 100}
    end
  end

  describe "pid_config/0" do
    test "returns the current pid's config as a map" do
      Mace.put_config(:my_app, :debug, true)
      config = Mace.pid_config()

      assert config == %{my_app: %{timeout: 100, debug: true}}
    end

    test "returns empty map when no config set" do
      Mace.reset()
      assert Mace.pid_config() == %{}
    end
  end
end

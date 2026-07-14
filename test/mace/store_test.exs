defmodule Mace.StoreTest do
  use ExUnit.Case, async: true

  describe "put/3 and fetch/3" do
    test "stores and retrieves a config override" do
      Mace.Store.put(:my_app, :timeout, 100)
      assert Mace.Store.fetch(self(), :my_app, :timeout) == {:ok, 100}
    end

    test "unlinked process sees no config" do
      Mace.Store.put(:my_app, :timeout, 100)

      parent = self()

      {:ok, _task} =
        Task.start(fn ->
          send(parent, {:result, Mace.Store.fetch(self(), :my_app, :timeout)})
        end)

      assert_receive {:result, :error}
    end

    test "returns :error for unknown key" do
      assert Mace.Store.fetch(self(), :my_app, :no_such_key) == :error
    end

    test "returns :error for unknown app" do
      assert Mace.Store.fetch(self(), :no_such_app, :timeout) == :error
    end

    test "overwrites existing value" do
      Mace.Store.put(:my_app, :timeout, 100)
      Mace.Store.put(:my_app, :timeout, 200)
      assert Mace.Store.fetch(self(), :my_app, :timeout) == {:ok, 200}
    end
  end

  describe "delete/1" do
    test "removes all config for a pid" do
      Mace.Store.put(:my_app, :timeout, 100)
      Mace.Store.delete(self())
      assert Mace.Store.fetch(self(), :my_app, :timeout) == :error
    end
  end

  describe "to_map/1" do
    test "returns empty map for pid with no config" do
      assert Mace.Store.to_map(self()) == %{}
    end

    test "returns all overrides for a pid as a map" do
      Mace.Store.put(:my_app, :timeout, 100)
      Mace.Store.put(:my_app, :debug, true)

      assert Mace.Store.to_map(self()) == %{
               my_app: %{timeout: 100, debug: true}
             }
    end
  end

  describe "load/1" do
    test "loads a config map into the current pid's store" do
      map = %{my_app: %{timeout: 100}}
      Mace.Store.load(map)

      assert Mace.Store.fetch(self(), :my_app, :timeout) == {:ok, 100}
    end
  end
end

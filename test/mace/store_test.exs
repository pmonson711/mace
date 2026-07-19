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

  describe "delete/2 and delete/3" do
    test "deletes a specific key from the pid's config" do
      Mace.Store.put(:my_app, :timeout, 100)
      Mace.Store.put(:my_app, :debug, true)

      Mace.Store.delete(self(), :my_app, :timeout)

      assert Mace.Store.fetch(self(), :my_app, :timeout) == {:ok, nil}
      assert Mace.Store.fetch(self(), :my_app, :debug) == {:ok, true}
    end

    test "sets key to tombstone, fetch returns nil" do
      Mace.Store.put(:my_app, :timeout, 100)

      Mace.Store.delete(self(), :my_app, :timeout)

      assert Mace.Store.fetch(self(), :my_app, :timeout) == {:ok, nil}
    end

    test "preserves other app entries" do
      Mace.Store.put(:my_app, :timeout, 100)
      Mace.Store.put(:other_app, :key, "val")

      Mace.Store.delete(self(), :my_app, :timeout)

      assert Mace.Store.fetch(self(), :other_app, :key) == {:ok, "val"}
    end

    test "delete/2 uses current process" do
      Mace.Store.put(:my_app, :timeout, 100)

      Mace.Store.delete(:my_app, :timeout)

      assert Mace.Store.fetch(self(), :my_app, :timeout) == {:ok, nil}
    end

    test "deleting non-existent key sets it to nil" do
      assert Mace.Store.delete(self(), :my_app, :no_such_key) == :ok
      assert Mace.Store.fetch(self(), :my_app, :no_such_key) == {:ok, nil}
    end

    test "Mace.delete sets the key to nil" do
      Mace.set(:my_app, :timeout, 100)
      Mace.set(:my_app, :debug, true)

      Mace.delete(:my_app, :timeout)

      assert Mace.get(:my_app, :timeout) == {:ok, nil}
      assert Mace.get(:my_app, :debug) == {:ok, true}
    end
  end

  describe "cache staleness" do
    test "cache is flushed when a config-registered process terminates" do
      Mace.Store.put(:my_app, :k1, "persists")

      parent = self()

      {:ok, victim} =
        Task.start(fn ->
          Mace.Store.put(:my_app, :k2, "ephemeral")
          send(parent, {:ready, self()})

          receive do
            :die -> :ok
          end
        end)

      assert_receive {:ready, ^victim}

      :ets.insert(:mace_neg_cache, {{self(), :my_app, :k1}, true})
      :ets.insert(:mace_neg_keys, {{:my_app, :k1}, self()})

      assert Mace.Store.fetch(self(), :my_app, :k1) == :error

      Process.exit(victim, :kill)
      Process.sleep(50)

      refute :ets.member(:mace_neg_cache, {self(), :my_app, :k1})
    end

    test "monitored process death enables fresh tree walk" do
      Mace.Store.put(:my_app, :k2, "from_deeper")

      parent = self()

      {:ok, intermediate} =
        Task.start(fn ->
          Mace.Store.put(:my_app, :k1, "from_intermediate")

          child =
            spawn(fn ->
              receive do
                :query -> send(parent, {:result, Mace.Store.fetch(self(), :my_app, :k2)})
              end
            end)

          Process.monitor(child)
          send(parent, {:intermediate_ready, child})

          receive do
            :die -> :ok
          end
        end)

      assert_receive {:intermediate_ready, child_pid}

      Process.monitor(child_pid)

      :ets.insert(:mace_neg_cache, {{child_pid, :my_app, :k2}, true})
      :ets.insert(:mace_neg_keys, {{:my_app, :k2}, child_pid})

      Process.exit(intermediate, :kill)
      Process.sleep(50)

      send(child_pid, :query)

      assert_receive {:result, {:ok, "from_deeper"}}
    end
  end

  describe "first-config-wins opacity" do
    test "child with partial config falls through to ancestor for missing keys" do
      Mace.Store.put(:my_app, :k2, "from_parent")

      parent = self()

      task =
        Task.async(fn ->
          Mace.Store.put(:my_app, :k1, "from_child")

          result = Mace.Store.fetch(self(), :my_app, :k2)
          send(parent, {:result, result})
        end)

      Task.await(task)

      assert_receive {:result, {:ok, "from_parent"}}
    end

    test "child with tombstones falls through to ancestor for other keys" do
      Mace.Store.put(:my_app, :k2, "from_parent")

      parent = self()

      task =
        Task.async(fn ->
          Mace.Store.delete(:my_app, :k1)

          result = Mace.Store.fetch(self(), :my_app, :k2)
          send(parent, {:result, result})
        end)

      Task.await(task)

      assert_receive {:result, {:ok, "from_parent"}}
    end
  end

  describe "tree walk" do
    test "inherits config via monitored_by chain (Task.async)" do
      Mace.Store.put(:my_app, :timeout, 100)
      parent = self()

      task =
        Task.async(fn ->
          send(parent, {:result, Mace.Store.fetch(self(), :my_app, :timeout)})
        end)

      Task.await(task)
      assert_receive {:result, {:ok, 100}}
    end

    test "inherits config through two levels of monitored_by" do
      Mace.Store.put(:my_app, :timeout, 100)
      parent = self()

      middle =
        Task.async(fn ->
          inner =
            Task.async(fn ->
              send(parent, {:result, Mace.Store.fetch(self(), :my_app, :timeout)})
            end)

          Task.await(inner)
        end)

      Task.await(middle)
      assert_receive {:result, {:ok, 100}}
    end

    test "stops at first pid with registered config in the chain" do
      Mace.Store.put(:my_app, :timeout, 100)

      parent = self()

      task =
        Task.async(fn ->
          Mace.Store.put(:my_app, :timeout, 999)

          inner =
            Task.async(fn ->
              send(parent, {:result, Mace.Store.fetch(self(), :my_app, :timeout)})
            end)

          Task.await(inner)
        end)

      Task.await(task)
      assert_receive {:result, {:ok, 999}}
    end

    test "self config takes priority over ancestor config" do
      Mace.Store.put(:my_app, :timeout, 100)
      parent = self()

      task =
        Task.async(fn ->
          Mace.Store.put(:my_app, :timeout, 200)
          send(parent, {:result, Mace.Store.fetch(self(), :my_app, :timeout)})
        end)

      Task.await(task)
      assert_receive {:result, {:ok, 200}}
    end

    test "returns :error when no config found anywhere in the chain" do
      parent = self()

      task =
        Task.async(fn ->
          send(parent, {:result, Mace.Store.fetch(self(), :my_app, :timeout)})
        end)

      Task.await(task)
      assert_receive {:result, :error}
    end

    test "to_map inherits via monitored_by chain" do
      Mace.Store.put(:my_app, :timeout, 100)
      parent = self()

      task =
        Task.async(fn ->
          send(parent, {:result, Mace.Store.to_map(self())})
        end)

      Task.await(task)
      assert_receive {:result, %{my_app: %{timeout: 100}}}
    end

    test "to_map returns empty map when no config anywhere in the chain" do
      parent = self()

      task =
        Task.async(fn ->
          send(parent, {:result, Mace.Store.to_map(self())})
        end)

      Task.await(task)
      assert_receive {:result, %{}}
    end

    test "deleting own config falls through to ancestor config" do
      Mace.Store.put(:my_app, :timeout, 100)
      parent = self()

      task =
        Task.async(fn ->
          Mace.Store.put(:my_app, :timeout, 999)
          Mace.Store.delete(self())
          send(parent, {:result, Mace.Store.fetch(self(), :my_app, :timeout)})
        end)

      Task.await(task)
      assert_receive {:result, {:ok, 100}}
    end

    test "to_map falls through to ancestor when own config is deleted" do
      Mace.Store.put(:my_app, :timeout, 100)
      parent = self()

      task =
        Task.async(fn ->
          Mace.Store.put(:my_app, :timeout, 999)
          Mace.Store.delete(self())
          send(parent, {:result, Mace.Store.to_map(self())})
        end)

      Task.await(task)
      assert_receive {:result, %{my_app: %{timeout: 100}}}
    end

    test "to_map from task with no config returns ancestor config" do
      Mace.Store.put(:my_app, :timeout, 100)
      parent = self()

      task =
        Task.async(fn ->
          send(parent, {:result, Mace.Store.to_map(self())})
        end)

      Task.await(task)
      assert_receive {:result, %{my_app: %{timeout: 100}}}
    end
  end

  describe "cross-group contamination" do
    test "unbounded link traversal reaches config across 3+ link hops" do
      parent = self()

      # Chain: a_task -> parent -> bridge -> b_task  (3 link hops)
      # b_task has config at hop 3. 2-hop cap blocks at bridge.
      bridge = spawn_link(fn -> Process.sleep(:infinity) end)

      _b_task =
        spawn(fn ->
          Process.link(bridge)
          Mace.Store.put(:my_app, :secret, "from_b")
          Process.sleep(:infinity)
        end)

      a_task =
        Task.async(fn ->
          send(parent, {:result, Mace.Store.fetch(self(), :my_app, :secret)})
        end)

      Task.await(a_task)

      # With :links, the walk: a_task -> parent -> bridge -> b_task = 3 hops.
      # With 2-hop link cap, blocked at bridge (3rd hop tagged :monitored_by).
      assert_receive {:result, :error}
    end

    test "nested task does not reach config 3+ link hops away" do
      parent = self()

      # Chain: a_task -> parent -> bridge -> b_task  (3 link hops)
      # 2-hop cap stops at bridge (tagged :monitored_by, can't follow links)
      bridge = spawn_link(fn -> Process.sleep(:infinity) end)

      _b_task =
        spawn(fn ->
          Process.link(bridge)
          Mace.Store.put(:my_app, :secret, "from_deep_b")
          Process.sleep(:infinity)
        end)

      a_task =
        Task.async(fn ->
          send(parent, {:result, Mace.Store.fetch(self(), :my_app, :secret)})
        end)

      Task.await(a_task)

      assert_receive {:result, :error}
    end
  end
end

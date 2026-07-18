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
    test "stale negative cache prevents re-walk after config becomes reachable" do
      Mace.Store.put(:my_app, :k1, "available")

      parent = self()

      task =
        Task.async(fn ->
          send(parent, {:child_pid, self()})
          receive do
            :query -> send(parent, {:result, Mace.Store.fetch(self(), :my_app, :k1)})
          end
        end)

      assert_receive {:child_pid, child_pid}

      # Simulate a cached miss — as if a previous query for k1 failed
      # before the config became reachable (e.g. after an ancestor terminated)
      :ets.insert(:mace_neg_cache, {{child_pid, :my_app, :k1}, true})
      :ets.insert(:mace_neg_keys, {{:my_app, :k1}, child_pid})

      send(task.pid, :query)
      Task.await(task)

      # FIXME: stale cache returns :error.
      # A fresh tree walk would find {:ok, "available"} from the parent.
      assert_receive {:result, {:ok, "available"}}
    end

    test "stale cache persists after closer ancestor terminates exposing deeper config" do
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

      # Also monitor child from the test process so it has a second
      # monitored_by path after intermediate terminates
      Process.monitor(child_pid)

      # Simulate the cache state after a query from child:
      # walk found intermediate (has k1, not k2) → miss cached
      :ets.insert(:mace_neg_cache, {{child_pid, :my_app, :k2}, true})
      :ets.insert(:mace_neg_keys, {{:my_app, :k2}, child_pid})

      # Terminate the intermediate. Registry removes its config silently —
      # no call to invalidate_cache. Cache is now stale.
      Process.exit(intermediate, :kill)

      # Child survives (monitored, not linked). A fresh walk would now
      # find the test process (has k2) via child's monitored_by.
      send(child_pid, :query)

      # FIXME: stale cache returns :error.
      # A fresh tree walk would find {:ok, "from_deeper"} via the test process.
      assert_receive {:result, {:ok, "from_deeper"}}
    end
  end

  describe "first-config-wins opacity" do
    test "child with partial config blocks ancestor config for missing keys" do
      # Parent has k2 but not k1
      Mace.Store.put(:my_app, :k2, "from_parent")

      parent = self()

      task =
        Task.async(fn ->
          # Child registers its own partial config
          Mace.Store.put(:my_app, :k1, "from_child")

          # Query a key the child does NOT have but the parent DOES
          result = Mace.Store.fetch(self(), :my_app, :k2)
          send(parent, {:result, result})
        end)

      Task.await(task)

      # FIXME: first-config-wins — the tree walk stops at the child
      # (which has config for k1), so it never reaches the parent's k2.
      # Returns :error instead of {:ok, "from_parent"}.
      assert_receive {:result, {:ok, "from_parent"}}
    end

    test "child with only tombstones blocks ancestor config" do
      Mace.Store.put(:my_app, :k2, "from_parent")

      parent = self()

      task =
        Task.async(fn ->
          # Child registers a tombstone for k1
          Mace.Store.delete(:my_app, :k1)

          result = Mace.Store.fetch(self(), :my_app, :k2)
          send(parent, {:result, result})
        end)

      Task.await(task)

      # FIXME: first-config-wins — the walk stops at the child because
      # it has registered config (even just a tombstone for a different key).
      # Returns :error instead of {:ok, "from_parent"}.
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
end

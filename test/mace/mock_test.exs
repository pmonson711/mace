defmodule Mace.MockTest do
  use ExUnit.Case, async: false

  setup do
    Mace.Store.init()
    Mace.Mock.install()
    Application.put_env(:mace, :test_key, :default_value)
    on_exit(fn -> Application.delete_env(:mace, :test_key) end)
    :ok
  end

  describe "get_env/2 with override" do
    test "returns overridden value when store has it" do
      Mace.Store.put(:mace, :test_key, :override_value)
      assert Application.get_env(:mace, :test_key) == :override_value
    end

    test "falls through to real Application when no override" do
      assert Application.get_env(:mace, :test_key) == :default_value
    end

    test "unlinked process sees no override" do
      Mace.Store.put(:mace, :test_key, :override_value)

      parent = self()

      {:ok, _task} =
        Task.start(fn ->
          send(parent, {:result, Application.get_env(:mace, :test_key)})
        end)

      assert_receive {:result, :default_value}
    end
  end

  describe "get_env/3 with default" do
    test "returns overridden value ignoring default" do
      Mace.Store.put(:mace, :test_key, :info)
      assert Application.get_env(:mace, :test_key, :debug) == :info
    end

    test "returns default when no override and key not set" do
      assert Application.get_env(:mace, :nonexistent_key, :fallback) == :fallback
    end
  end

  describe "get_all_env/1" do
    test "merges overrides into real env" do
      Mace.Store.put(:mace, :test_key, :override_value)
      all = Application.get_all_env(:mace)

      assert all[:test_key] == :override_value
    end
  end

  describe "fetch_env/2" do
    test "returns override via fetch_env" do
      Mace.Store.put(:mace, :test_key, :warning)
      assert Application.fetch_env(:mace, :test_key) == {:ok, :warning}
    end

    test "falls through for unknown key" do
      assert Application.fetch_env(:mace, :nonexistent_key) == :error
    end
  end

  describe "uninstall/0" do
    test "after uninstall, Application.get_env bypasses the mock" do
      Mace.Store.put(:mace, :test_key, :override_value)
      Mace.Mock.uninstall()

      assert Application.get_env(:mace, :test_key) == :default_value
    end
  end
end

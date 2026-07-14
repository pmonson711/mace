defmodule MaceTest do
  use ExUnit.Case, async: true

  setup do
    Mace.Store.init()
    on_exit(fn -> Mace.Store.delete(self()) end)
    :ok
  end

  describe "set/3 and get/2" do
    test "sets and retrieves a simple scalar config value" do
      Mace.set(:my_app, :timeout, 100)
      assert Mace.get(:my_app, :timeout) == {:ok, 100}
    end

    test "returns :error for unset config" do
      assert Mace.get(:my_app, :timeout) == :error
    end
  end

  describe "set/2 and get/2" do
    test "sets multiple config values in a keyword list" do
      Mace.set(:my_app, timeout: 100, debug: true, retries: 3)

      assert Mace.get(:my_app, :timeout) == {:ok, 100}
      assert Mace.get(:my_app, :debug) == {:ok, true}
      assert Mace.get(:my_app, :retries) == {:ok, 3}
    end

    test "raises on invalid keyword list" do
      assert_raise ArgumentError, fn ->
        Mace.set(:my_app, "not a keyword")
      end
    end
  end

  describe "reset/0" do
    test "clears all config for the current process" do
      Mace.set(:my_app, :timeout, 100)
      Mace.set(:my_app, :debug, true)

      Mace.reset()

      assert Mace.get(:my_app, :timeout) == :error
      assert Mace.get(:my_app, :debug) == :error
    end
  end

  describe "diff/1" do
    test "returns formatted diff string when overrides differ" do
      real_truncate = Application.get_env(:logger, :truncate)
      Mace.set(:logger, :truncate, real_truncate + 1)
      diff = Mace.diff(:logger)

      assert diff =~ "logger"
      assert diff =~ "truncate"
      assert diff =~ "#{real_truncate + 1}"
    end

    test "returns empty diff when overrides match defaults" do
      real_truncate = Application.get_env(:logger, :truncate)
      Mace.set(:logger, :truncate, real_truncate)
      diff = Mace.diff(:logger)

      assert diff == ""
    end
  end
end

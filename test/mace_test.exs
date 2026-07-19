defmodule MaceTest do
  use ExUnit.Case, async: true

  setup do
    Mace.Store.init()
    :ok
  end

  describe "set/3 and get/2" do
    test "sets and retrieves a simple scalar config value" do
      Mace.put_config(:my_app, :timeout, 100)
      assert Mace.get_config(:my_app, :timeout) == {:ok, 100}
    end

    test "returns :error for unset config" do
      assert Mace.get_config(:my_app, :timeout) == :error
    end
  end

  describe "set/2 and get/2" do
    test "sets multiple config values in a keyword list" do
      Mace.put_config(:my_app, timeout: 100, debug: true, retries: 3)

      assert Mace.get_config(:my_app, :timeout) == {:ok, 100}
      assert Mace.get_config(:my_app, :debug) == {:ok, true}
      assert Mace.get_config(:my_app, :retries) == {:ok, 3}
    end

    test "raises on invalid keyword list" do
      assert_raise ArgumentError, fn ->
        Mace.put_config(:my_app, "not a keyword")
      end
    end
  end

  describe "reset/0" do
    test "clears all config for the current process" do
      Mace.put_config(:my_app, :timeout, 100)
      Mace.put_config(:my_app, :debug, true)

      Mace.reset()

      assert Mace.get_config(:my_app, :timeout) == :error
      assert Mace.get_config(:my_app, :debug) == :error
    end
  end

  describe "diff/1" do
    test "returns formatted diff string when overrides differ" do
      real_truncate = Application.get_env(:logger, :truncate)
      Mace.put_config(:logger, :truncate, real_truncate + 1)
      diff = Mace.diff(:logger)

      assert diff =~ "logger"
      assert diff =~ "truncate"
      assert diff =~ "#{real_truncate + 1}"
    end

    test "returns empty diff when overrides match defaults" do
      real_truncate = Application.get_env(:logger, :truncate)
      Mace.put_config(:logger, :truncate, real_truncate)
      diff = Mace.diff(:logger)

      assert diff == ""
    end
  end
end

defmodule Mace.PutEnvTest do
  use ExUnit.Case, async: true

  setup_all do
    Mace.Mock.install(put_env: true)
    :ok
  end

  setup do
    Mace.enable_put_env_intercept()
    on_exit(fn ->
      Mace.disable_put_env_intercept()
      Mace.reset()
    end)
    :ok
  end

  test "put_env writes to process store" do
    Application.put_env(:test_app, :key1, "value1")
    assert Mace.Store.fetch(self(), :test_app, :key1) == {:ok, "value1"}
  end

  test "get_env sees put_env value" do
    Application.put_env(:test_app, :timeout, 100)
    assert Application.get_env(:test_app, :timeout) == 100
  end

  test "put_all_env writes multiple values" do
    Application.put_all_env(:test_app, timeout: 100, debug: true)
    assert Application.get_env(:test_app, :timeout) == 100
    assert Application.get_env(:test_app, :debug) == true
  end

  test "delete_env writs tombstone" do
    Application.put_env(:test_app, :key1, "value1")
    Application.delete_env(:test_app, :key1)
    assert Application.get_env(:test_app, :key1) == nil
  end

  test "when disabled, put_env falls through to real module" do
    Mace.disable_put_env_intercept()
    Application.put_env(:test_app, :should_not_appear, "nope")
    Mace.enable_put_env_intercept()
  end

  test "does not leak between tests when async" do
    refute Application.get_env(:test_app, :leak_key)
  end
end

defmodule Mace.SystemEnvTest do
  use ExUnit.Case, async: true

  setup_all do
    Mace.Mock.install(system_env: true)
    :ok
  end

  setup do
    Mace.enable_system_env_intercept()

    on_exit(fn ->
      Mace.disable_system_env_intercept()
      Mace.reset()
    end)

    :ok
  end

  test "get_env sees overridden value" do
    System.put_env("MACE_TEST_VAR", "override")
    assert System.get_env("MACE_TEST_VAR") == "override"
  end

  test "get_env returns nil for unknown var" do
    assert System.get_env("MACE_NONEXISTENT_VAR") == nil
  end

  test "get_env with default uses override" do
    System.put_env("MACE_TEST_VAR", "override")
    assert System.get_env("MACE_TEST_VAR", "default") == "override"
  end

  test "get_env with default returns default when missing" do
    assert System.get_env("MACE_NONEXISTENT", "default") == "default"
  end

  test "get_env/0 merges overrides with real env" do
    System.put_env("MACE_TEST_VAR", "merged_value")
    full_env = System.get_env()
    assert full_env["MACE_TEST_VAR"] == "merged_value"
  end

  test "put_env map form works" do
    System.put_env(%{"MACE_A" => "val_a", "MACE_B" => "val_b"})
    assert System.get_env("MACE_A") == "val_a"
    assert System.get_env("MACE_B") == "val_b"
  end

  test "delete_env removes override" do
    System.put_env("MACE_TEMP", "temp")
    System.delete_env("MACE_TEMP")
    assert System.get_env("MACE_TEMP") == nil
  end

  test "does not leak between async tests" do
    refute System.get_env("MACE_LEAK_KEY")
  end
end

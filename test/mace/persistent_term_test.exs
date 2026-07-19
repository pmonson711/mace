defmodule Mace.PersistentTermTest do
  use ExUnit.Case, async: true

  setup_all do
    :persistent_term.put(:mace_test_real, "real_value")
    Mace.Mock.install(persistent_term: true)
    on_exit(fn -> :persistent_term.erase(:mace_test_real) end)
    :ok
  end

  setup do
    Mace.enable_persistent_term_intercept()
    on_exit(fn ->
      Mace.disable_persistent_term_intercept()
      Mace.reset()
    end)
    :ok
  end

  test "get sees overridden value" do
    :persistent_term.put(:mace_test_key, "override")
    assert :persistent_term.get(:mace_test_key) == "override"
  end

  test "get falls through to real when no override" do
    assert :persistent_term.get(:mace_test_real) == "real_value"
  end

  test "get with default uses override" do
    :persistent_term.put(:mace_test_key, "override")
    assert :persistent_term.get(:mace_test_key, "default") == "override"
  end

  test "erase removes override" do
    :persistent_term.put(:mace_test_key, "value")
    :persistent_term.erase(:mace_test_key)
    assert :persistent_term.get(:mace_test_key, :not_found) == :not_found
  end

  test "does not leak between async tests" do
    assert :persistent_term.find(:mace_test_leak_key) == :error
  end
end

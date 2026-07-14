defmodule Mace.DiffTest do
  use ExUnit.Case, async: true

  describe "snapshot/1" do
    test "captures all env for a loaded application" do
      snapshot = Mace.Diff.snapshot(:logger)
      assert is_map(snapshot)
      assert Map.has_key?(snapshot, :truncate)
    end

    test "returns empty map for unknown application" do
      assert Mace.Diff.snapshot(:nonexistent_app) == %{}
    end
  end

  describe "compute/2" do
    test "returns empty diff when no overrides" do
      snapshot = %{timeout: 5000, debug: false}
      overrides = %{}
      diff = Mace.Diff.compute(snapshot, overrides)
      assert diff == %{}
    end

    test "shows only changed keys" do
      snapshot = %{timeout: 5000, debug: false, retries: 3}
      overrides = %{timeout: 100, debug: true}
      diff = Mace.Diff.compute(snapshot, overrides)
      assert diff == %{timeout: {5000, 100}, debug: {false, true}}
    end

    test "handles keys in override not present in snapshot" do
      snapshot = %{timeout: 5000}
      overrides = %{timeout: 100, new_key: "value"}
      diff = Mace.Diff.compute(snapshot, overrides)
      assert diff == %{timeout: {5000, 100}, new_key: {:__not_set__, "value"}}
    end

    test "omits keys where override matches snapshot" do
      snapshot = %{timeout: 5000, debug: false}
      overrides = %{timeout: 5000, debug: true}
      diff = Mace.Diff.compute(snapshot, overrides)
      assert diff == %{debug: {false, true}}
    end
  end

  describe "format/2" do
    test "formats a diff map as readable string" do
      diff = %{timeout: {5000, 100}, debug: {false, true}}
      formatted = Mace.Diff.format(:my_app, diff)

      assert formatted =~ ":my_app"
      assert formatted =~ "timeout"
      assert formatted =~ "5000"
      assert formatted =~ "100"
      assert formatted =~ "debug"
      assert formatted =~ "false"
      assert formatted =~ "true"
    end

    test "returns empty string for empty diff" do
      assert Mace.Diff.format(:my_app, %{}) == ""
    end
  end
end

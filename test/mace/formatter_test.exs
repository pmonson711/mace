defmodule Mace.FormatterTest do
  use ExUnit.Case, async: true

  setup do
    Mace.Store.init()
    Mace.Formatter.reset()
    on_exit(fn -> Mace.Store.delete(self()) end)
    :ok
  end

  describe "record/2" do
    test "stores diff for a test identified by module + name" do
      Mace.set(:logger, :truncate, 42)
      Mace.Formatter.record(Mace.FormatterTest, :some_test)

      diffs = Mace.Formatter.lookup(Mace.FormatterTest, :some_test)
      assert diffs =~ "truncate"
      assert diffs =~ "42"
    end

    test "stores nothing when no overrides" do
      Mace.Formatter.record(Mace.FormatterTest, :empty_test)

      diffs = Mace.Formatter.lookup(Mace.FormatterTest, :empty_test)
      assert diffs == ""
    end
  end

  describe "clear/2" do
    test "removes recorded diff" do
      Mace.set(:logger, :truncate, 42)
      Mace.Formatter.record(Mace.FormatterTest, :clear_me)
      Mace.Formatter.clear(Mace.FormatterTest, :clear_me)

      assert Mace.Formatter.lookup(Mace.FormatterTest, :clear_me) == ""
    end
  end

  describe "cleanup/1" do
    test "records diffs and resets config" do
      Mace.set(:logger, :truncate, 42)

      Mace.cleanup(%{module: Mace.FormatterTest, test: :cleanup_test})

      assert Mace.get(:logger, :truncate) == :error

      diffs = Mace.Formatter.lookup(Mace.FormatterTest, :cleanup_test)
      assert diffs =~ "truncate"
    end
  end
end

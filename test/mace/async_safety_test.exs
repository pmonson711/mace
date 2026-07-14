defmodule Mace.AsyncSafetyTest do
  use ExUnit.Case, async: true

  setup_all do
    Mace.Mock.install()
    :ok
  end

  setup do
    Mace.Store.init()
    on_exit(fn -> Mace.reset() end)
    :ok
  end

  alias Mace.Support.AsyncDemoApp

  describe "async config isolation" do
    test "test A sets override" do
      Mace.set(:mace, :test_level, :level_a)
      Process.sleep(10)
      assert AsyncDemoApp.get_level() == :level_a
    end

    test "test B sets different override" do
      Mace.set(:mace, :test_level, :level_b)
      Process.sleep(10)
      assert AsyncDemoApp.get_level() == :level_b
    end

    test "unrelated test sees no override" do
      result = AsyncDemoApp.get_level()
      assert result == nil || result not in [:level_a, :level_b]
    end
  end
end

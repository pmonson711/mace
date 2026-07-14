defmodule Mace.Support.AsyncDemoApp do
  @moduledoc false

  def get_level do
    Application.get_env(:mace, :test_level)
  end
end

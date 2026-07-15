defmodule Mace.Diff do
  @moduledoc false

  @doc """
  Captures a snapshot of all env for a loaded application.
  Returns a map of `key => value`.
  """
  def snapshot(app) do
    case Application.loaded_applications()
         |> Enum.find(fn {a, _, _} -> a == app end) do
      nil -> %{}
      _ -> Enum.into(Application.get_all_env(app), %{})
    end
  end

  @doc """
  Computes a diff between the snapshot (application defaults) and overrides.
  Returns a map of `key => {default_value, override_value}` for changed keys.
  Keys in overrides not present in snapshot use `:__not_set__` as default.
  """
  def compute(snapshot, overrides) do
    Enum.reduce(overrides, %{}, fn {key, override_val}, acc ->
      default_val = Map.get(snapshot, key, :__not_set__)

      if default_val != override_val,
        do: Map.put(acc, key, {default_val, override_val}),
        else: acc
    end)
  end

  @doc """
  Formats a diff map into a human-readable string for ExUnit output.
  Returns empty string for empty diffs.
  """
  def format(_app, diff) when map_size(diff) == 0, do: ""

  def format(app, diff) do
    header = "\n\nTest config diff for #{inspect(app)}:\n"
    separator = String.duplicate("─", 50) <> "\n"

    body =
      diff
      |> Enum.map(fn {key, {default, override}} ->
        default_str = format_value(default)
        override_str = format_value(override)
        "  #{inspect(key)}:  #{default_str} (default)  →  #{override_str} (test)"
      end)
      |> Enum.join("\n")

    header <> separator <> body <> "\n" <> separator
  end

  defp format_value(:__not_set__), do: "<not set>"
  defp format_value(value), do: inspect(value)
end

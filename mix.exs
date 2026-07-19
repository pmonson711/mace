defmodule Mace.MixProject do
  use Mix.Project

  def project do
    [
      app: :mace,
      version: "0.1.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description:
        "Per-test config isolation for ExUnit with transparent Application.get_env interception",
      package: package(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:meck, "~> 0.9"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/pmonson711/mace"},
      source_url: "https://github.com/pmonson711/mace"
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url_pattern: "https://github.com/pmonson711/mace/blob/master/%{path}#L%{line}"
    ]
  end
end

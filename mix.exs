defmodule ZapierSDK.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/jamescarr/zapier_sdk_ex"

  def project do
    [
      app: :zapier_sdk,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      package: package(),
      description:
        "Unofficial Elixir SDK for Zapier. Run Zapier actions over HTTP with " <>
          "concurrency, streaming, and telemetry. No Node.js required.",

      # Docs
      name: "ZapierSDK",
      source_url: @source_url,
      docs: docs(),

      # Static analysis
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ZapierSDK.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.7"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},

      # Dev/Test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.16", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Zapier SDK docs" => "https://docs.zapier.com/sdk"
      },
      maintainers: ["James Carr"]
    ]
  end

  defp docs do
    [
      main: "ZapierSDK",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      groups_for_modules: [
        Core: [
          ZapierSDK,
          ZapierSDK.Connection,
          ZapierSDK.Action,
          ZapierSDK.Result,
          ZapierSDK.Error
        ],
        Configuration: [
          ZapierSDK.Config,
          ZapierSDK.Auth
        ],
        "App Helpers": [
          ZapierSDK.Apps.Jira,
          ZapierSDK.Apps.Slack,
          ZapierSDK.Apps.GoogleDrive,
          ZapierSDK.Apps.GoogleCalendar,
          ZapierSDK.Apps.Coda
        ],
        Internals: [
          ZapierSDK.Client,
          ZapierSDK.Catalog,
          ZapierSDK.HTTP,
          ZapierSDK.Telemetry
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      # Fixed, cacheable location so CI can restore the PLT across runs
      # instead of rebuilding it (from scratch) on every job.
      plt_core_path: "priv/plts",
      plt_local_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "compile --warnings-as-errors", "credo --strict"],
      # Everything CI runs, in one command, so it can be reproduced locally.
      # `test` and the `hex.*` tasks are shelled out via `cmd` (each its own
      # `mix` process) rather than chained directly: `mix test` needs to run
      # under MIX_ENV=test regardless of what env `check` itself was invoked
      # under, and `hex.audit`/`deps.unlock` only get Hex's archive on the
      # code path when they're the top-level CLI task, not when run as a
      # step inside another alias.
      check: [
        "lint",
        "cmd mix hex.audit",
        "cmd mix deps.unlock --check-unused",
        "dialyzer",
        "cmd env MIX_ENV=test mix test"
      ]
    ]
  end
end

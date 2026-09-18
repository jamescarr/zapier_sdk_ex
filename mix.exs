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
      docs: docs()
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

  defp aliases do
    [
      lint: ["format --check-formatted", "compile --warnings-as-errors"]
    ]
  end
end

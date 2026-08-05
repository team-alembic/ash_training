defmodule Twitter.MixProject do
  use Mix.Project

  def project do
    [
      app: :twitter,
      version: "0.1.0",
      elixir: "~> 1.14",
      consolidate_protocols: false,
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      compilers: [:phoenix_live_view] ++ Mix.compilers()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Twitter.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Ash
      {:ash, "~> 3.0"},
      {:ash_admin, "~> 1.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_graphql, "~> 1.0"},
      {:ash_json_api, "~> 1.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},
      {:redoc_ui_plug, "~> 0.2"},
      {:open_api_spex, "~> 3.16"},
      # Phoenix Default Dependencies
      {:bandit, "~> 1.5"},
      {:dns_cluster, "~> 0.2"},
      {:ecto_sql, "~> 3.10"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:gettext, "~> 1.0"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:igniter, "~> 0.8", only: :dev},
      {:jason, "~> 1.2"},
      {:lazy_html, ">= 0.0.0", only: :test},
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:picosat_elixir, "~> 0.2"},
      {:postgrex, ">= 0.0.0"},
      {:swoosh, "~> 1.5"},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:ecto_dev_logger, "~> 0.10"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build"],
      test: ["ash.setup --quiet", "ash.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind twitter", "esbuild twitter"],
      "assets.deploy": [
        "tailwind twitter --minify",
        "esbuild twitter --minify",
        "phx.digest"
      ]
    ]
  end
end

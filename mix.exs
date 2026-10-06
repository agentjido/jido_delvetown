defmodule JidoDelvetown.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_delvetown,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {JidoDelvetown.Application, []}
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:jido_action, path: "../jido_action", override: true},
      {:jido_signal, path: "../jido_signal", override: true},
      {:jido, path: "../jido", override: true},
      {:jido_ai, path: "../jido_ai", override: true},
      {:jido_character,
       git: "https://github.com/agentjido/jido_character.git",
       ref: "8652d217e7755a2865d3ec8275e8a5025f9d245f"},
      {:zoi, path: "../zoi", override: true},
      {:imp, "0.8.1"},
      {:req_llm, "~> 1.26"},
      {:phoenix_playground, "~> 0.1.9"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.24.1"},
      {:oban, "~> 2.24"},
      {:proto_rune, "~> 0.6.0"},
      {:jason, "~> 1.4"},
      {:dotenvy, "~> 1.2"},
      {:sourceror, "~> 1.7", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "xref graph --format cycles --label compile-connected"
      ]
    ]
  end
end

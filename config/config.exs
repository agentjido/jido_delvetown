import Config

config :jido_delvetown,
  dashboard_enabled: config_env() != :test,
  legacy_import_enabled: config_env() != :test,
  ecto_repos: [JidoDelvetown.Repo]

if config_env() == :test do
  database =
    Path.join(
      System.tmp_dir!(),
      "jido_delvetown_test_#{System.pid()}_#{System.unique_integer([:positive])}.sqlite3"
    )

  config :jido_delvetown,
    database_path: database

  config :jido_delvetown, JidoDelvetown.Repo,
    pool_size: 1,
    queue_target: 5_000
end

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

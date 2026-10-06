import Config

config :jido_delvetown,
  legacy_import_enabled: config_env() != :test,
  ecto_repos: [JidoDelvetown.Repo]

oban_config = [
  engine: Oban.Engines.Lite,
  repo: JidoDelvetown.Repo,
  queues: [delvetown: 1],
  cron: [
    crontab: [
      {"*/15 * * * *", JidoDelvetown.Workers.ReactiveParticipationWorker},
      {"5,35 * * * *", JidoDelvetown.Workers.ProactiveReviewWorker},
      {"7 * * * *", JidoDelvetown.Workers.MemberDiscoveryWorker},
      {"17 * * * *", JidoDelvetown.Workers.FriendSyncWorker}
    ]
  ],
  lifeline: [rescue_after: {5, :minutes}],
  pruner: [max_age: {30, :days}]
]

if config_env() == :test do
  database =
    Path.join(
      System.tmp_dir!(),
      "jido_delvetown_test_#{System.pid()}_#{System.unique_integer([:positive])}.sqlite3"
    )

  config :jido_delvetown,
    database_path: database,
    dashboard_server: JidoDelvetown.Test.DashboardServer

  config :jido_delvetown, JidoDelvetown.Repo,
    pool_size: 1,
    queue_target: 5_000

  config :jido_delvetown, Oban, Keyword.put(oban_config, :testing, :manual)
else
  config :jido_delvetown, Oban, oban_config
end

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import Config

config :jido_delvetown,
  dashboard_enabled: config_env() != :test

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

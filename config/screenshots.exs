import Config

config :bolognesa, :music_refresh_dispatcher, false
config :bolognesa, :music_import_reconciler, false

config :bolognesa, Bolognesa.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: String.to_integer(System.get_env("BOLOGNESA_SCREENSHOT_DB_PORT", "5433")),
  database: "bolognesa_screenshots",
  pool_size: 10

config :bolognesa, BolognesaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4001"))],
  check_origin: false,
  secret_key_base: "readme-screenshots-only-not-a-production-secret-base-32-bytes-minimum"

config :bolognesa,
       :library_roots,
       System.get_env(
         "BOLOGNESA_LIBRARY_ROOTS",
         Path.join(System.tmp_dir!(), "bolognesa-screenshots")
       )
       |> String.split(":", trim: true)

config :bolognesa,
       :transcode_root,
       System.get_env(
         "BOLOGNESA_TRANSCODE_ROOT",
         Path.join(System.tmp_dir!(), "bolognesa-screenshots-transcode")
       )

config :bolognesa, :scan_reconciler, false
config :bolognesa, :inspection_outbox_dispatcher, false
config :bolognesa, :identification_outbox_dispatcher, false
config :bolognesa, :inspection_reconciler, false
config :bolognesa, :identification_reconciler, false
config :bolognesa, Oban, testing: :manual, queues: false, plugins: false
config :logger, level: :warning

config :swoosh, :api_client, false

import Config

config :bolognesa, Oban, testing: :manual, queues: false, plugins: false
config :bolognesa, :inspection_outbox_dispatcher, false
config :bolognesa, :identification_outbox_dispatcher, false
config :bolognesa, :inspection_reconciler, false
config :bolognesa, :identification_reconciler, false
config :bolognesa, :scan_reconciler, false

config :bolognesa, :library_roots, [Path.join(System.tmp_dir!(), "bolognesa-library-test")]

config :bcrypt_elixir, :log_rounds, 4

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :bolognesa, Bolognesa.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "bolognesa_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # Committed concurrency tests hold a sandbox owner, a coordinator and three workers.
  # Keep five connections available even on runners with one or two schedulers.
  pool_size: max(System.schedulers_online() * 2, 5)

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bolognesa, BolognesaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tdaGYJHVHhiHLCj+8xy4vcGTjVVBL/7F+dUPNppkg7OvDxMG3cWrvrHh1cgCJyhv",
  server: false

# In test we don't send emails
config :bolognesa, Bolognesa.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

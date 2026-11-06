# LiveView async work includes cold module loading and database round trips.
# Wait for completion without treating ExUnit's 100ms default as a latency contract.
ExUnit.start(assert_receive_timeout: 1_000)
Ecto.Adapters.SQL.Sandbox.mode(Bolognesa.Repo, :manual)

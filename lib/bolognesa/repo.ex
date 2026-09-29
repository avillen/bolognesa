defmodule Bolognesa.Repo do
  use Ecto.Repo,
    otp_app: :bolognesa,
    adapter: Ecto.Adapters.Postgres
end

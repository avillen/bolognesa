defmodule Bolognesa.Identity.Infrastructure.Persistence.SessionSchema do
  @moduledoc false
  use Ecto.Schema

  schema "identity_sessions" do
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    belongs_to :user, Bolognesa.Identity.Infrastructure.Persistence.UserSchema
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end

defmodule Bolognesa.Infrastructure.Persistence.SessionSchema do
  @moduledoc false
  use Ecto.Schema

  @type t :: %__MODULE__{
          user:
            Bolognesa.Infrastructure.Persistence.UserSchema.t()
            | Ecto.Association.NotLoaded.t()
        }

  schema "identity_sessions" do
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    belongs_to :user, Bolognesa.Infrastructure.Persistence.UserSchema
    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end

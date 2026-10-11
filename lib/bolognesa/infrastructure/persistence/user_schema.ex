defmodule Bolognesa.Infrastructure.Persistence.UserSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          email: String.t() | nil,
          role: String.t() | nil,
          hashed_password: String.t() | nil,
          locale: String.t() | nil
        }

  schema "identity_users" do
    field :name, :string
    field :email, :string
    field :role, :string
    field :locale, :string
    field :hashed_password, :string, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email])
    |> validate_required([:name, :email, :role, :hashed_password])
    |> unique_constraint(:email)
    |> unique_constraint(:role, name: :identity_one_admin)
  end
end

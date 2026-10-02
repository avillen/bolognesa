defmodule Bolognesa.Identity.Infrastructure.Persistence.UserSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "identity_users" do
    field :name, :string
    field :email, :string
    field :role, :string
    field :hashed_password, :string, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email])
    |> validate_required([:name, :email, :role, :hashed_password])
    |> unique_constraint(:email)
    |> unique_constraint(:role, name: :identity_one_admin)
  end
end

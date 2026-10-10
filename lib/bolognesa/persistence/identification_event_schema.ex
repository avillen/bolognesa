defmodule Bolognesa.Persistence.IdentificationEventSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "media_identification_events" do
    field :media_file_id, :id
    field :token, Ecto.UUID
    field :delivered_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> change(attrs)
    |> validate_required([:media_file_id, :token])
    |> foreign_key_constraint(:media_file_id)
    |> unique_constraint([:media_file_id, :token])
  end
end

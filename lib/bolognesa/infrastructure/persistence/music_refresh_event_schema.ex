defmodule Bolognesa.Infrastructure.Persistence.MusicRefreshEventSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "music_refresh_events" do
    field :media_file_id, :id
    field :revision, :integer
    field :inspection_token, Ecto.UUID
    field :delivered_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(row, attrs), do: change(row, attrs)
end

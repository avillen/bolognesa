defmodule Bolognesa.Infrastructure.Persistence.MusicArtistSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "music_artists" do
    field :library_id, :id
    field :name, :string
    field :normalized_name, :string
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> change(attrs)
    |> unique_constraint([:library_id, :normalized_name])
  end
end

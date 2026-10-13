defmodule Bolognesa.Infrastructure.Persistence.MusicTrackSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "music_tracks" do
    field :media_file_id, :id
    field :library_id, :id
    field :title, :string
    field :artist_id, :id
    field :album_id, :id
    field :disc_number, :integer
    field :track_number, :integer
    field :year, :integer
    field :observed_revision, :integer
    field :inspection_token, Ecto.UUID
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> change(attrs)
    |> unique_constraint(:media_file_id)
    |> check_constraint(:observed_revision, name: :music_tracks_revision_positive)
    |> check_constraint(:track_number, name: :music_tracks_number_valid)
    |> check_constraint(:disc_number, name: :music_tracks_disc_valid)
  end
end

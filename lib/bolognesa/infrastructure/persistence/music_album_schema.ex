defmodule Bolognesa.Infrastructure.Persistence.MusicAlbumSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "music_albums" do
    field :library_id, :id
    field :source_parent, :binary
    field :title, :string
    field :normalized_title, :string
    field :artist_id, :id
    field :album_artist_key, :string
    field :year, :integer
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> change(attrs)
    |> unique_constraint([:library_id, :source_parent, :normalized_title, :album_artist_key],
      name: :music_albums_grouping_index
    )
  end
end

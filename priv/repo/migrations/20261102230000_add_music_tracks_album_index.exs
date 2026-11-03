defmodule Bolognesa.Repo.Migrations.AddMusicTracksAlbumIndex do
  use Ecto.Migration

  def change do
    create index(:music_tracks, [:album_id])
  end
end

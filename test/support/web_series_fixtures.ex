defmodule BolognesaWeb.SeriesFixtures do
  @moduledoc false
  alias Bolognesa.Identity
  alias Bolognesa.Infrastructure.LocalSourcePath

  alias Bolognesa.Infrastructure.Persistence.{
    EpisodeSchema,
    LibrarySchema,
    MediaFileSchema,
    SeasonSchema
  }

  alias Bolognesa.Repo
  alias Bolognesa.SeriesFixtures
  @spec setup(Plug.Conn.t()) :: map()
  def setup(conn) do
    {:ok, actor} =
      Identity.install_admin(%{
        name: "Ada",
        email: "series@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("series@example.com", "correct horse battery staple")
    root = hd(Application.fetch_env!(:bolognesa, :library_roots))
    directory = Path.join(root, "series-web-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    {:ok, physical} = LocalSourcePath.canonical_directory(directory)
    name = "Serie S00E01E02.mp4"
    File.write!(Path.join(physical, name), "abcdefgh")
    {:ok, stat} = File.stat(Path.join(physical, name), time: :posix)
    library = Repo.insert!(%LibrarySchema{name: "Series", path: physical, content_type: :series})

    file =
      Repo.insert!(%MediaFileSchema{
        library_id: library.id,
        relative_path: name,
        size_bytes: 8,
        modified_at: DateTime.from_unix!(stat.mtime * 1_000_000, :microsecond),
        availability: :available,
        revision: 1,
        last_seen_generation: Ecto.UUID.generate()
      })

    decision = SeriesFixtures.identify(file, 0, [1, 2])
    episode = Repo.get!(EpisodeSchema, hd(decision.catalog_entry_ids))
    season = Repo.get!(SeasonSchema, episode.season_id)

    %{
      conn: Plug.Test.init_test_session(conn, user_token: token),
      token: token,
      actor: actor,
      library: library,
      media_file: file,
      episode_id: episode.id,
      episode_ids: decision.catalog_entry_ids,
      season_id: season.id,
      series_id: season.series_id,
      directory: directory
    }
  end
end

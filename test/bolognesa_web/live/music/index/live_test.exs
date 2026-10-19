defmodule BolognesaWeb.Music.Index.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Bolognesa.MusicFixtures
  alias Bolognesa.Accounts
  alias Bolognesa.Repo

  setup do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "music@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Accounts.start_session("music@example.com", "correct horse battery staple")
    %{token: token}
  end

  test "lists tagged and fallback titles and selects native authenticated audio", %{
    conn: conn,
    token: token
  } do
    fixture = refresh_fixture(tags: %{"title" => "Sample Song", "artist" => "Sample Artist"})

    {:ok, view, _} =
      live(init_test_session(conn, user_token: token), "/music?library_id=#{fixture.library.id}")

    render_async(view)
    assert has_element?(view, "#music-tracks", "Sample Song")
    assert has_element?(view, "#music-tracks", "Sample Artist")
    view |> element("#play-track-#{fixture.track.id}") |> render_click()
    assert has_element?(view, "#music-player-frame[phx-hook=AudioPlayer][phx-update=ignore]")
    assert has_element?(view, "#music-player-frame media-i18n[lang=es]")
    assert has_element?(view, "audio#music-player[controls]")
    assert has_element?(view, "#now-playing", "Sample Song")

    assert has_element?(
             view,
             "audio#music-player source[src='/music/tracks/#{fixture.track.id}/media/#{fixture.file.id}']"
           )

    refute has_element?(view, "audio[autoplay]")
    render_hook(view, "audio-error", %{})
    assert has_element?(view, "#audio-error")
  end

  test "cross-type library selection redirects and empty music libraries remain selectable", %{
    conn: conn,
    token: token
  } do
    fixture = music_fixture(availability: :missing)

    {:ok, view, _} =
      live(init_test_session(conn, user_token: token), "/music?library_id=#{fixture.library.id}")

    render_async(view)
    assert has_element?(view, "#music-empty")
    assert has_element?(view, "a[href='/music?library_id=#{fixture.library.id}']")

    assert {:error, {:live_redirect, %{to: "/libraries"}}} =
             live(
               init_test_session(conn, user_token: token),
               "/movies?library_id=#{fixture.library.id}"
             )
  end

  test "processing, inspection failure and changed-source feedback remain distinct", %{
    conn: conn,
    token: token
  } do
    pending = music_fixture(inspection_state: :pending)
    failed = music_fixture(inspection_state: :failed)
    ready = refresh_fixture()
    {:ok, view, _} = live(init_test_session(conn, user_token: token), "/music")
    render_async(view)
    assert has_element?(view, "#tracks-#{pending.file.id}[data-state=pending]")
    assert has_element?(view, "#tracks-#{failed.file.id}[data-state=inspection_failed]")
    Repo.update!(Ecto.Changeset.change(ready.file, revision: 2))
    view |> element("#play-track-#{ready.track.id}") |> render_click()
    refute has_element?(view, "audio#music-player")
    assert has_element?(view, "[role=alert]")
  end

  test "browse artist albums and advance through the album queue", %{conn: conn, token: token} do
    f =
      refresh_fixture(
        tags: %{"artist" => "Ensemble", "album" => "First", "title" => "Opening", "track" => "1"}
      )

    second =
      music_fixture(
        relative_path: "album/second.mp3",
        tags: %{"artist" => "Ensemble", "album" => "First", "title" => "Finale", "track" => "2"}
      )

    Repo.update!(Ecto.Changeset.change(second.file, library_id: f.library.id))
    :ok = Bolognesa.Music.refresh_track(second.file.id, 1)

    {:ok, view, _} =
      live(
        init_test_session(conn, user_token: token),
        "/music?library_id=#{f.library.id}&view=artists"
      )

    render_async(view)
    view |> element("#artist-#{f.track.artist_id}") |> render_click()
    render_async(view)
    assert has_element?(view, "#album-#{f.track.album_id}", "First")
    view |> element("#album-#{f.track.album_id}") |> render_click()
    render_async(view)
    assert has_element?(view, "#music-tracks", "Finale")
    view |> element("#play-album") |> render_click()
    render_async(view)
    assert has_element?(view, "#now-playing", "Opening")
    render_hook(view, "audio-ended", %{"generation" => player_generation(view)})
    assert has_element?(view, "#now-playing", "Finale")
    render_hook(view, "audio-ended", %{"generation" => player_generation(view)})
    assert has_element?(view, "#queue-finished")
  end

  test "unavailable album entries allow next and stale ended events cannot skip tracks", %{
    conn: conn,
    token: token
  } do
    f =
      refresh_fixture(
        tags: %{
          "artist" => "Ensemble",
          "album" => "First",
          "title" => "Unavailable",
          "track" => "1"
        }
      )

    second =
      music_fixture(
        relative_path: "album/second.mp3",
        tags: %{
          "artist" => "Ensemble",
          "album" => "First",
          "title" => "Available",
          "track" => "2"
        }
      )

    Repo.update!(Ecto.Changeset.change(second.file, library_id: f.library.id))
    :ok = Bolognesa.Music.refresh_track(second.file.id, 1)
    Repo.update!(Ecto.Changeset.change(f.file, revision: 2))

    {:ok, view, _} =
      live(
        init_test_session(conn, user_token: token),
        "/music?library_id=#{f.library.id}&view=album&album_id=#{f.track.album_id}"
      )

    render_async(view)
    view |> element("#play-album") |> render_click()
    render_async(view)
    assert has_element?(view, "#audio-error", "Unavailable")
    view |> element("#queue-next") |> render_click()
    assert has_element?(view, "#now-playing", "Available")
    render_hook(view, "audio-ended", %{"generation" => "1"})
    refute has_element?(view, "#queue-finished")
    view |> element("#queue-previous") |> render_click()
    assert has_element?(view, "#audio-error", "Unavailable")
    refute has_element?(view, "#music-player")
    refute has_element?(view, "#now-playing", "Available")
  end

  defp player_generation(view) do
    view
    |> element("#music-player-frame")
    |> render()
    |> then(fn html -> Regex.run(~r/data-generation="([^"]+)"/, html) |> Enum.at(1) end)
  end
end

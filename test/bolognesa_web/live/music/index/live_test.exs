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

  test "opens the artist tab by default and allows switching to songs", %{
    conn: conn,
    token: token
  } do
    fixture = refresh_fixture(tags: %{"title" => "Sample Song", "artist" => "Sample Artist"})

    {:ok, view, _} =
      live(init_test_session(conn, user_token: token), "/music?library_id=#{fixture.library.id}")

    render_async(view)
    assert has_element?(view, "#music-artists-link[aria-current=page]")
    assert has_element?(view, "#music-browse", "Sample Artist")
    view |> element("#music-songs-link") |> render_click()
    render_async(view)
    assert has_element?(view, "#music-songs-link[aria-current=page]")
    assert has_element?(view, "#music-tracks", "Sample Song")
  end

  test "lists tagged tracks with authorized client actions", %{conn: conn, token: token} do
    fixture = refresh_fixture(tags: %{"title" => "Sample Song", "artist" => "Sample Artist"})

    {:ok, view, _} =
      live(
        init_test_session(conn, user_token: token),
        "/music?library_id=#{fixture.library.id}&view=tracks"
      )

    render_async(view)
    assert has_element?(view, "#music-screen[phx-hook=AudioPlayer]")
    assert has_element?(view, "#music-tracks", "Sample Song")
    assert has_element?(view, "#music-tracks", "Sample Artist")

    assert has_element?(
             view,
             "#play-track-#{fixture.track.id}[data-music-action=track][data-track-id='#{fixture.track.id}'][data-file-id='#{fixture.file.id}']"
           )

    assert has_element?(view, "#tracks-#{fixture.file.id}[data-state=ready]")
    refute has_element?(view, "#music-screen button[phx-click=play]")
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
    {:ok, view, _} = live(init_test_session(conn, user_token: token), "/music?view=tracks")
    render_async(view)
    assert has_element?(view, "#tracks-#{pending.file.id}[data-state=pending]")
    assert has_element?(view, "#tracks-#{failed.file.id}[data-state=inspection_failed]")
    Repo.update!(Ecto.Changeset.change(ready.file, revision: 2))
    assert has_element?(view, "#play-track-#{ready.track.id}[data-music-action=track]")
  end

  test "browse artist albums and expose an album play command", %{conn: conn, token: token} do
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

    assert has_element?(
             view,
             "#play-album[data-music-action=album][data-album-id='#{f.track.album_id}']"
           )
  end

  test "unavailable album entries stay visible while track controls remain client-side", %{
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
    assert has_element?(view, "#play-album[data-music-action=album]")
    assert has_element?(view, "#tracks-#{f.file.id}[data-state=pending]")

    assert has_element?(
             view,
             "#tracks-#{second.file.id} .music-track-play[data-music-action=track]"
           )
  end
end

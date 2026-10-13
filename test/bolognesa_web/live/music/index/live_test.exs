defmodule BolognesaWeb.Music.Index.LiveTest do
  use BolognesaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Bolognesa.MusicFixtures
  alias Bolognesa.Identity
  alias Bolognesa.Repo

  setup do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "music@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("music@example.com", "correct horse battery staple")
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
    assert has_element?(view, "audio#music-player[controls]")

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
end

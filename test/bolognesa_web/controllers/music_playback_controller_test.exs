defmodule BolognesaWeb.MusicPlaybackControllerTest do
  alias Bolognesa.Music, as: BolognesaMusic
  alias Bolognesa.MusicFixtures
  alias Bolognesa.Repo
  use BolognesaWeb.ConnCase, async: false
  import Bolognesa.MusicFixtures
  alias Bolognesa.Accounts
  alias Bolognesa.Music.Infrastructure.Repositories.EctoListeningActivityRepository

  setup %{conn: conn} do
    {:ok, _} =
      Accounts.install_admin(%{
        name: "Ada",
        email: "music-playback@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} =
      Accounts.start_session("music-playback@example.com", "correct horse battery staple")

    {:ok, conn: conn, token: token}
  end

  test "authorized track operation returns only public metadata and a local route", %{
    conn: conn,
    token: token
  } do
    fixture = refresh_fixture(tags: %{"title" => "Synthetic title", "artist" => "Example artist"})
    conn = authenticated_with_csrf(conn, token)

    response =
      json_post(conn, "/music/playback/track", %{
        track_id: fixture.track.id,
        file_id: fixture.file.id
      })

    assert response.status == 200

    assert %{
             "track" => %{"id" => track_id, "file_id" => file_id, "title" => "Synthetic title"},
             "src" => source
           } = Jason.decode!(response.resp_body)

    assert track_id == fixture.track.id
    assert file_id == fixture.file.id
    assert source == "/music/tracks/#{fixture.track.id}/media/#{fixture.file.id}"
    refute response.resp_body =~ fixture.file.relative_path
    refute response.resp_body =~ fixture.library.path
  end

  test "anonymous selection is rejected as JSON when CSRF is valid", %{conn: conn} do
    conn = get(conn, "/login")

    csrf =
      Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, response(conn, 200)) |> Enum.at(1)

    conn = recycle(conn)

    response =
      conn
      |> put_req_header("x-csrf-token", csrf)
      |> json_post("/music/playback/track", %{track_id: 1, file_id: 1})

    assert response.status == 401
    assert Jason.decode!(response.resp_body) == %{"error" => %{"code" => "unauthenticated"}}
  end

  test "invalid and mismatched IDs never expose a source", %{conn: conn, token: token} do
    fixture = refresh_fixture()
    conn = authenticated_with_csrf(conn, token)
    invalid = json_post(conn, "/music/playback/track", %{track_id: -1, file_id: fixture.file.id})
    assert invalid.status == 400

    mismatched =
      json_post(conn, "/music/playback/track", %{
        track_id: fixture.track.id,
        file_id: fixture.file.id + 100
      })

    assert mismatched.status == 404
    refute mismatched.resp_body =~ "src"
  end

  test "qualifying playback records one latest value for the account and track", %{
    conn: conn,
    token: token
  } do
    fixture = refresh_fixture()
    conn = authenticated_with_csrf(conn, token)

    for _ <- 1..2 do
      response =
        json_post(conn, "/music/playback/activity", %{
          track_id: fixture.track.id,
          file_id: fixture.file.id
        })

      assert response.status == 200
    end

    assert %{rows: [[played_at]]} =
             Repo.query!(
               "SELECT last_played_at FROM music_listening_activity WHERE track_id = $1",
               [fixture.track.id]
             )

    assert :ok = BolognesaMusic.refresh_track(fixture.file.id, fixture.file.revision)

    assert %{rows: [[^played_at]]} =
             Repo.query!(
               "SELECT last_played_at FROM music_listening_activity WHERE track_id = $1",
               [fixture.track.id]
             )
  end

  test "activity rejects an unrelated file", %{conn: conn, token: token} do
    fixture = refresh_fixture()
    conn = authenticated_with_csrf(conn, token)

    response =
      json_post(conn, "/music/playback/activity", %{
        track_id: fixture.track.id,
        file_id: fixture.file.id + 1
      })

    assert response.status == 404
  end

  test "listening rows are independent across accounts", %{conn: conn, token: token} do
    fixture = refresh_fixture()
    conn = authenticated_with_csrf(conn, token)

    assert json_post(conn, "/music/playback/activity", %{
             track_id: fixture.track.id,
             file_id: fixture.file.id
           }).status == 200

    %{rows: [[other_id]]} =
      Repo.query!("""
      INSERT INTO accounts_users (name, email, role, hashed_password, locale, inserted_at, updated_at)
      VALUES ('Other', 'other@example.com', 'member', 'unused', 'en', now(), now()) RETURNING id
      """)

    assert :ok =
             EctoListeningActivityRepository.record(
               other_id,
               fixture.track.id
             )

    assert :ok =
             EctoListeningActivityRepository.record(
               other_id,
               fixture.track.id
             )

    assert %{rows: [[2]]} =
             Repo.query!(
               "SELECT count(*) FROM music_listening_activity WHERE track_id = $1",
               [fixture.track.id]
             )
  end

  defp authenticated_with_csrf(conn, token) do
    conn = conn |> init_test_session(user_token: token) |> get("/")

    csrf =
      Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, response(conn, 200)) |> Enum.at(1)

    conn |> recycle() |> put_req_header("x-csrf-token", csrf)
  end

  defp json_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> post(path, Jason.encode!(body))
  end
end

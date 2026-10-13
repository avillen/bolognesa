defmodule BolognesaWeb.MusicMediaControllerTest do
  use BolognesaWeb.ConnCase, async: false

  alias Bolognesa.Identity

  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Repo

  import Bolognesa.MusicFixtures

  setup do
    {:ok, _} =
      Identity.install_admin(%{
        name: "Ada",
        email: "music@example.com",
        password: "correct horse battery staple"
      })

    {:ok, token} = Identity.start_session("music@example.com", "correct horse battery staple")
    fixture = refresh_fixture(relative_path: "sample.mp3")
    base = hd(Application.fetch_env!(:bolognesa, :library_roots))
    directory = Path.join(base, "music-http-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, physical} = LocalSourcePath.canonical_directory(directory)
    physical_file = Path.join(physical, "sample.mp3")
    File.write!(physical_file, "abcdefgh")
    stat = File.stat!(physical_file, time: :posix)
    modified_at = DateTime.from_unix!(stat.mtime * 1_000_000, :microsecond)
    Repo.update!(Ecto.Changeset.change(fixture.library, path: physical))

    file =
      Repo.update!(Ecto.Changeset.change(fixture.file, size_bytes: 8, modified_at: modified_at))

    {:ok, token: token, movie: fixture.track, media_file: file, physical_file: physical_file}
  end

  test "serves full content and one valid range with private headers", %{
    conn: conn,
    token: token,
    movie: movie,
    media_file: file
  } do
    path = ~p"/music/tracks/#{movie.id}/media/#{file.id}"

    full =
      conn
      |> init_test_session(user_token: token)
      |> put_req_header("accept", "audio/mpeg")
      |> get(path)

    assert response(full, 200) == "abcdefgh"
    assert get_resp_header(full, "accept-ranges") == ["bytes"]
    assert get_resp_header(full, "cache-control") == ["private, no-store"]
    assert get_resp_header(full, "content-type") == ["audio/mpeg"]

    ranged =
      conn
      |> init_test_session(user_token: token)
      |> put_req_header("range", "bytes=2-4")
      |> get(path)

    assert response(ranged, 206) == "cde"
    assert get_resp_header(ranged, "content-range") == ["bytes 2-4/8"]
    assert get_resp_header(ranged, "content-length") == ["3"]

    suffix =
      conn
      |> init_test_session(user_token: token)
      |> put_req_header("range", "bytes=-2")
      |> get(path)

    assert response(suffix, 206) == "gh"

    open =
      conn
      |> init_test_session(user_token: token)
      |> put_req_header("range", "bytes=6-")
      |> get(path)

    assert response(open, 206) == "gh"
  end

  test "HEAD returns headers without a body and invalid ranges return no bytes", %{
    conn: conn,
    token: token,
    movie: movie,
    media_file: file
  } do
    path = ~p"/music/tracks/#{movie.id}/media/#{file.id}"
    head_conn = conn |> init_test_session(user_token: token) |> head(path)
    assert head_conn.status == 200
    assert head_conn.state == :sent
    assert response(head_conn, 200) == ""
    assert get_resp_header(head_conn, "content-length") == ["8"]

    outside =
      conn
      |> init_test_session(user_token: token)
      |> put_req_header("range", "bytes=8-")
      |> get(path)

    assert outside.status == 416
    assert get_resp_header(outside, "content-range") == ["bytes */8"]
    refute response(outside, 416) =~ "abcdefgh"

    for range <- ["bytes=0-1,4-5", "bytes=wat"] do
      invalid =
        conn
        |> init_test_session(user_token: token)
        |> put_req_header("range", range)
        |> get(path)

      assert invalid.status == 400
      refute response(invalid, 400) =~ "abcdefgh"
    end
  end

  test "denies missing or revoked sessions and another movie", %{
    conn: conn,
    token: token,
    movie: movie,
    media_file: file
  } do
    path = ~p"/music/tracks/#{movie.id}/media/#{file.id}"
    assert conn |> get(path) |> response(401) == ""

    other = refresh_fixture().track

    wrong_path = ~p"/music/tracks/#{other.id}/media/#{file.id}"
    assert conn |> init_test_session(user_token: token) |> get(wrong_path) |> response(404) == ""

    assert :ok = Identity.end_session(token)
    assert conn |> init_test_session(user_token: token) |> get(path) |> response(401) == ""
  end

  test "does not serve a file changed after inventory", %{
    conn: conn,
    token: token,
    movie: movie,
    media_file: file,
    physical_file: physical_file
  } do
    File.write!(physical_file, "different content")
    path = ~p"/music/tracks/#{movie.id}/media/#{file.id}"
    result = conn |> init_test_session(user_token: token) |> get(path)
    assert result.status in [404, 409]
    refute response(result, result.status) =~ "different content"
  end
end

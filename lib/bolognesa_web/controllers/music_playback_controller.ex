defmodule BolognesaWeb.MusicPlaybackController do
  use BolognesaWeb, :controller
  require Logger

  alias Bolognesa.Music
  alias Bolognesa.Playback

  @max_safe_integer 9_007_199_254_740_991
  @error_responses %{
    unauthenticated: {401, :unauthenticated},
    forbidden: {403, :forbidden},
    invalid_query: {400, :invalid_request},
    invalid_request: {400, :invalid_request},
    not_found: {404, :not_found},
    missing: {404, :not_found},
    album_too_large: {422, :album_too_large},
    unavailable: {503, :unavailable}
  }

  def track(conn, %{"track_id" => track_id, "file_id" => file_id}) do
    with {:ok, actor} <- actor(conn),
         :ok <- validate_ids(track_id, file_id),
         {:ok, _source} <- Playback.start_track(actor, track_id, file_id),
         {:ok, track} <- Music.fetch_track(actor, track_id),
         :ok <- matching_file(track.file_id, file_id) do
      json(conn, %{
        track: public_track(track),
        src: ~p"/music/tracks/#{track_id}/media/#{file_id}"
      })
    else
      {:error, reason} ->
        error(conn, reason)

      _other ->
        Logger.error("music playback selection failed", reason: :unexpected)
        error(conn, :unavailable)
    end
  end

  def track(conn, _params), do: error(conn, :invalid_request)

  def activity(conn, %{"track_id" => track_id, "file_id" => file_id}) do
    with {:ok, actor} <- actor(conn),
         :ok <- validate_ids(track_id, file_id),
         {:ok, _source} <- Playback.start_track(actor, track_id, file_id),
         :ok <- Music.record_listening(actor, track_id, file_id) do
      json(conn, %{ok: true})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  def activity(conn, _params), do: error(conn, :invalid_request)

  def album(conn, %{"album_id" => album_id} = params) do
    library_id = Map.get(params, "library_id")

    with {:ok, actor} <- actor(conn),
         true <- valid_id?(album_id) and (is_nil(library_id) or valid_id?(library_id)),
         {:ok, tracks} <- Music.album_queue(actor, album_id, library_id) do
      json(conn, %{tracks: Enum.map(tracks, &public_track/1)})
    else
      false -> error(conn, :invalid_request)
      {:error, reason} -> error(conn, reason)
    end
  end

  def album(conn, _params), do: error(conn, :invalid_request)

  defp actor(%{assigns: %{current_scope: %{actor: actor}}}) when not is_nil(actor),
    do: {:ok, actor}

  defp actor(_conn), do: {:error, :unauthenticated}

  defp validate_ids(track_id, file_id) do
    if valid_id?(track_id) and valid_id?(file_id), do: :ok, else: {:error, :invalid_request}
  end

  defp matching_file(file_id, file_id), do: :ok
  defp matching_file(_, _), do: {:error, :not_found}

  defp valid_id?(value), do: is_integer(value) and value > 0 and value <= @max_safe_integer

  defp public_track(track) do
    %{
      id: track.id,
      file_id: track.file_id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration_ms: track.duration_ms,
      state: track.state
    }
  end

  defp error(conn, reason) do
    {status, code} = Map.get(@error_responses, reason, {503, :unavailable})

    conn |> put_status(status) |> json(%{error: %{code: code}})
  end
end

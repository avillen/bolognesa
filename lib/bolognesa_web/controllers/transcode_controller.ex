defmodule BolognesaWeb.TranscodeController do
  use BolognesaWeb, :controller

  alias Bolognesa.Playback
  alias Bolognesa.Playback.Infrastructure.TranscodeManager

  @segment ~r/\Aseg-[0-9]{6,12}\.ts\z/

  @spec manifest(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def manifest(conn, params),
    do: serve(conn, params, "index.m3u8", "application/vnd.apple.mpegurl")

  @spec segment(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def segment(conn, %{"segment" => name} = params) do
    if Regex.match?(@segment, name),
      do: serve(conn, params, name, "video/mp2t"),
      else: reject_with_event(conn, :segment, :request_validation, :invalid_segment, 404)
  end

  defp serve(conn, _params, name, mime_type) do
    with {:ok, movie_id} <- positive_id(entry_param(conn.path_params)),
         {:ok, file_id} <- positive_id(conn.path_params["file_id"]),
         {:ok, session} <-
           Playback.video_compatible_session(
             conn.assigns.current_scope.actor,
             {entry_kind(conn.path_params), movie_id},
             file_id,
             conn.path_params["session_id"]
           )
           |> stage(:session_validation),
         {:ok, bytes} <- stage(read(session.directory, name), :resource_read),
         :ok <- stage(touch_segment(session.id, name), :session_touch) do
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_content_type(mime_type)
      |> send_resp(200, bytes)
    else
      {:error, stage, reason} ->
        reject_with_event(conn, resource_type(name), stage, reason, status(reason))

      _ ->
        reject_with_event(conn, resource_type(name), :request_validation, :invalid_reference, 404)
    end
  end

  defp stage({:error, reason}, stage), do: {:error, stage, reason}
  defp stage(result, _stage), do: result

  defp status(:unavailable), do: 503
  defp status(:source_changed), do: 409
  defp status(_reason), do: 404

  defp resource_type("index.m3u8"), do: :manifest
  defp resource_type(_name), do: :segment

  defp reject_with_event(conn, resource_type, stage, reason, status) do
    :telemetry.execute([:bolognesa, :playback, :hls, :failed], %{count: 1}, %{
      session_id: safe_session_id(conn.path_params["session_id"]),
      resource_type: resource_type,
      failure_stage: stage,
      reason: reason,
      status: status
    })

    reject(conn, status)
  end

  defp safe_session_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  defp touch_segment(_id, "index.m3u8"), do: :ok
  defp touch_segment(id, _name), do: TranscodeManager.touch(id)

  defp read(directory, name) do
    path = Path.join(directory, name)

    case File.lstat(path) do
      {:ok, %{type: :regular}} -> File.read(path)
      _ -> {:error, :not_found}
    end
  end

  defp entry_kind(%{"movie_id" => _}), do: :movie
  defp entry_kind(%{"episode_id" => _}), do: :episode
  defp entry_kind(_), do: :invalid

  defp entry_param(%{"movie_id" => id}), do: id
  defp entry_param(%{"episode_id" => id}), do: id
  defp entry_param(_), do: nil

  defp positive_id(text) when is_binary(text) do
    case Integer.parse(text) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :not_found}
    end
  end

  defp positive_id(_), do: {:error, :not_found}

  defp reject(conn, status) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(status, "")
  end
end

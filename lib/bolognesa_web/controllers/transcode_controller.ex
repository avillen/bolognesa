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
      else: reject(conn, 404)
  end

  defp serve(conn, params, name, mime_type) do
    with {:ok, catalog_entry_id} <- positive_id(params["movie_id"]),
         {:ok, file_id} <- positive_id(params["file_id"]),
         {:ok, session} <-
           Playback.compatible_session(
             conn.assigns.current_scope.actor,
             catalog_entry_id,
             file_id,
             params["session_id"]
           ),
         {:ok, bytes} <- read(session.directory, name),
         :ok <- touch_segment(session.id, name) do
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_content_type(mime_type)
      |> send_resp(200, bytes)
    else
      {:error, :unavailable} -> reject(conn, 503)
      {:error, :source_changed} -> reject(conn, 409)
      _ -> reject(conn, 404)
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

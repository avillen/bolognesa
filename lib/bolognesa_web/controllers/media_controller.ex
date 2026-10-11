defmodule BolognesaWeb.MediaController do
  use BolognesaWeb, :controller

  alias Bolognesa.Playback
  alias Bolognesa.Playback.Domain.ByteRange
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile

  @chunk_size 65_536
  @mime_types %{
    ".mp4" => "video/mp4",
    ".m4v" => "video/mp4",
    ".mkv" => "video/x-matroska",
    ".avi" => "video/x-msvideo",
    ".mov" => "video/quicktime",
    ".webm" => "video/webm",
    ".mpeg" => "video/mpeg",
    ".mpg" => "video/mpeg",
    ".ts" => "video/mp2t",
    ".m2ts" => "video/mp2t"
  }

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"movie_id" => movie_text, "file_id" => file_text}) do
    actor = conn.assigns.current_scope.actor

    with {:ok, catalog_entry_id} <- positive_id(movie_text),
         {:ok, file_id} <- positive_id(file_text),
         {:ok, source} <- Playback.start(actor, catalog_entry_id, file_id),
         {:ok, mime_type} <- mime_type(source.relative_path),
         {:ok, opened} <- LocalMediaFile.open(source) do
      try do
        serve(conn, opened, mime_type)
      after
        :file.close(opened.device)
      end
    else
      {:error, reason} -> error_response(conn, reason)
    end
  end

  defp positive_id(text) do
    case Integer.parse(text) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  defp mime_type(relative_path) do
    case Map.fetch(@mime_types, relative_path |> Path.extname() |> String.downcase()) do
      {:ok, mime} -> {:ok, mime}
      :error -> {:error, :unsupported}
    end
  end

  defp serve(conn, %{device: device, size: size}, mime_type) do
    case requested_range(conn) do
      {:ok, range} -> send_range(conn, device, size, mime_type, range)
      {:error, :invalid} -> error_response(conn, :invalid_range)
    end
  end

  defp requested_range(conn) do
    case get_req_header(conn, "range") do
      [] -> {:ok, nil}
      [range] -> {:ok, range}
      _ -> {:error, :invalid}
    end
  end

  defp send_range(conn, device, size, mime_type, range) do
    case ByteRange.parse(range, size) do
      {:ok, {offset, length, status}} ->
        conn =
          conn
          |> put_resp_header("cache-control", "private, no-store")
          |> put_resp_header("accept-ranges", "bytes")
          |> put_resp_header("content-type", mime_type)
          |> put_resp_header("content-length", Integer.to_string(length))
          |> maybe_content_range(status, offset, length, size)

        if conn.private[:original_method] == "HEAD" do
          send_resp(conn, status, "")
        else
          conn |> send_chunked(status) |> stream_range(device, offset, length)
        end

      {:error, :invalid} ->
        error_response(conn, :invalid_range)

      {:error, :unsatisfiable} ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> error_response(:unsatisfiable)
    end
  end

  defp maybe_content_range(conn, 206, offset, length, size) do
    put_resp_header(conn, "content-range", "bytes #{offset}-#{offset + length - 1}/#{size}")
  end

  defp maybe_content_range(conn, _, _, _, _), do: conn

  defp stream_range(conn, _device, _offset, 0), do: conn

  defp stream_range(conn, device, offset, remaining) do
    case :file.pread(device, offset, min(@chunk_size, remaining)) do
      {:ok, bytes} when byte_size(bytes) > 0 ->
        case chunk(conn, bytes) do
          {:ok, conn} ->
            stream_range(conn, device, offset + byte_size(bytes), remaining - byte_size(bytes))

          {:error, _} ->
            conn
        end

      _ ->
        conn
    end
  end

  defp error_response(conn, reason) do
    status =
      case reason do
        :forbidden -> 403
        :unavailable -> 503
        :source_inaccessible -> 503
        :source_changed -> 409
        :invalid_range -> 400
        :unsatisfiable -> 416
        :unsupported -> 415
        _ -> 404
      end

    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(status, "")
  end
end

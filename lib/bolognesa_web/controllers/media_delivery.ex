defmodule BolognesaWeb.MediaDelivery do
  @moduledoc "Authorized-source byte responses using one validated file descriptor."
  import Plug.Conn
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ValueObjects.ByteRange
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile

  @type error ::
          :forbidden
          | :not_found
          | :missing
          | :unavailable
          | :unsupported
          | :invalid_range
          | :unsatisfiable
          | LocalMediaFile.failure()
  @chunk_size 65_536
  @spec serve(Plug.Conn.t(), Source.t(), String.t()) :: Plug.Conn.t()
  def serve(conn, source, mime_type) do
    case LocalMediaFile.open(source) do
      {:ok, opened} ->
        try do
          serve_opened(conn, opened, mime_type)
        after
          :file.close(opened.device)
        end

      {:error, reason} ->
        error_response(conn, reason)
    end
  end

  defp serve_opened(conn, %{device: device, size: size}, mime_type) do
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

  @spec error_response(Plug.Conn.t(), error()) :: Plug.Conn.t()
  def error_response(conn, reason) do
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

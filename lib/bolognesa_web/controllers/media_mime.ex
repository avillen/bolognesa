defmodule BolognesaWeb.MediaMime do
  @moduledoc "Explicit MIME policy for direct media delivery."
  @mime_types %{
    ".mp3" => "audio/mpeg",
    ".m4a" => "audio/mp4",
    ".aac" => "audio/aac",
    ".flac" => "audio/flac",
    ".ogg" => "audio/ogg",
    ".opus" => "audio/ogg",
    ".wav" => "audio/wav",
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

  @type error :: :unsupported
  @spec for_path(binary(), :video | :music) :: {:ok, String.t()} | {:error, error()}
  def for_path(relative_path, kind \\ :video) do
    case Map.fetch(@mime_types, relative_path |> Path.extname() |> String.downcase()) do
      {:ok, mime} -> permitted(mime, kind)
      :error -> {:error, :unsupported}
    end
  end

  defp permitted("audio/" <> _ = mime, :music), do: {:ok, mime}
  defp permitted("video/" <> _ = mime, :video), do: {:ok, mime}
  defp permitted(_mime, _kind), do: {:error, :unsupported}
end

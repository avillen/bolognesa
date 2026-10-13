defmodule BolognesaWeb.MediaMime do
  @moduledoc "Explicit MIME policy for direct media delivery."
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

  @type error :: :unsupported
  @spec for_path(binary()) :: {:ok, String.t()} | {:error, error()}
  def for_path(relative_path) do
    case Map.fetch(@mime_types, relative_path |> Path.extname() |> String.downcase()) do
      {:ok, mime} -> {:ok, mime}
      :error -> {:error, :unsupported}
    end
  end
end

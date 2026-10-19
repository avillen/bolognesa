defmodule Bolognesa.Libraries.Infrastructure.Services.FfprobeMediaProbe do
  @moduledoc "Probes a validated physical file and rechecks it after the command."
  @behaviour Bolognesa.Libraries.Application.Ports.Services.MediaProbe

  require Logger

  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Libraries.Infrastructure.Services.BoundedCommand
  alias Bolognesa.Libraries.Infrastructure.Services.FfprobeJson

  @timeout_ms 30_000
  @max_bytes 262_144
  @args [
    "-v",
    "quiet",
    "-show_format",
    "-show_streams",
    "-show_entries",
    "format=format_name,duration:stream=index,codec_type,codec_name,width,height,channels:stream_tags=language",
    "-of",
    "json"
  ]

  @impl true
  def inspect(library, file), do: inspect(library, file, [])

  @spec inspect(
          Bolognesa.Libraries.Domain.Entities.Library.t(),
          Bolognesa.Libraries.Domain.Entities.MediaFile.t(),
          keyword()
        ) ::
          {:ok, Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalMedia.t()}
          | {:error, Bolognesa.Libraries.Application.Ports.Services.MediaProbe.reason()}
  def inspect(library, file, opts) do
    with {:ok, root, source_identity} <- source(library.path),
         {:ok, path, before_identity} <- physical_file(root, file),
         {:ok, media} <- probe(path, library.content_type, opts),
         {:ok, after_root, after_source_identity} <- source(library.path),
         :ok <- same?(root, after_root),
         :ok <- same?(source_identity, after_source_identity),
         {:ok, after_path, after_identity} <- physical_file(after_root, file),
         :ok <- same?(path, after_path),
         :ok <- same?(before_identity, after_identity) do
      {:ok, media}
    else
      {:error, :failed} ->
        log_read_failure(file, :ffprobe)
        {:error, :unreadable}

      {:error, :unreadable} = error ->
        log_read_failure(file, :file_access)
        error

      {:error, :too_large} ->
        {:error, :invalid_output}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp probe(path, content_type, opts) do
    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :timeout_ms, @timeout_ms)
    opts = Keyword.put(opts, :probe_deadline_ms, deadline)

    with {:ok, output} <- run_probe(path, content_type, opts, []) do
      parse_probe(output, path, content_type, opts)
    end
  end

  defp parse_probe(output, path, content_type, opts) do
    case FfprobeJson.parse(output, content_type || :movie) do
      {:error, :invalid_output} = error ->
        retry_mp3(error, output, path, content_type, opts)

      result ->
        result
    end
  end

  defp retry_mp3(error, output, path, :music, opts) do
    with true <- Path.extname(path) in [".mp3", ".MP3"],
         {:ok, %{"format" => %{"format_name" => "mpeg"}}} <- Jason.decode(output) do
      probe_mp3(path, opts)
    else
      _ -> error
    end
  end

  defp retry_mp3(error, _output, _path, _content_type, _opts), do: error

  defp probe_mp3(path, opts) do
    with {:ok, output} <- run_probe(path, :music, opts, ["-f", "mp3"]) do
      FfprobeJson.parse(output, :music)
    end
  end

  defp run_probe(path, content_type, opts, input_args) do
    remaining_ms = Keyword.fetch!(opts, :probe_deadline_ms) - System.monotonic_time(:millisecond)

    if remaining_ms > 0 do
      BoundedCommand.run(
        Keyword.get(opts, :executable, System.find_executable("ffprobe") || "ffprobe"),
        args(content_type) ++ input_args ++ [path],
        remaining_ms,
        Keyword.get(opts, :max_bytes, @max_bytes)
      )
    else
      {:error, :timeout}
    end
  end

  defp log_read_failure(file, stage) do
    Logger.warning("Technical media inspection failed",
      file_id: file.id,
      failure_stage: stage,
      failure_reason: :unreadable
    )
  end

  defp args(:music) do
    Enum.map(@args, fn
      "format=" <> _ = entries ->
        String.replace(
          entries,
          "stream_tags=language",
          "stream_disposition=attached_pic:stream_tags=language,title,artist,album_artist,albumartist,album,disc,discnumber,track,tracknumber,date,year"
        ) <>
          ":format_tags=title,artist,album_artist,albumartist,album,disc,discnumber,track,tracknumber,date,year"

      arg ->
        arg
    end)
  end

  defp args(_type), do: @args

  defp source(path) do
    with {:ok, root} <- LocalSourcePath.canonical_directory(path),
         :ok <- same?(root, path),
         :ok <- source_ancestors(root),
         {:ok, stat} <- File.stat(root, time: :posix) do
      {:ok, root, identity(stat)}
    else
      {:error, :source_changed} = error -> error
      _ -> {:error, :source_inaccessible}
    end
  end

  defp source_ancestors(root) do
    case physical_ancestors("", Enum.reject(Path.split(root), &(&1 == "/"))) do
      :ok -> :ok
      _ -> {:error, :source_inaccessible}
    end
  end

  defp physical_file(root, file) do
    parts = :binary.split(file.relative_path, "/", [:global])

    if Enum.any?(parts, &(&1 in ["", ".", ".."])) do
      {:error, :unsafe_entry}
    else
      validated_physical_file(root, file, parts)
    end
  end

  defp validated_physical_file(root, file, parts) do
    with :ok <- physical_ancestors(root, Enum.drop(parts, -1)),
         path = root <> "/" <> file.relative_path,
         {:ok, %{type: :regular, access: access} = stat} <- File.lstat(path, time: :posix),
         true <- access in [:read, :read_write],
         {:ok, modified_at} <- DateTime.from_unix(stat.mtime),
         :ok <- same?(file.size_bytes, stat.size),
         :ok <- same?(file.modified_at, modified_at) do
      {:ok, path, identity(stat)}
    else
      {:ok, _} -> {:error, :unsafe_entry}
      false -> {:error, :unreadable}
      {:error, :source_changed} = error -> error
      {:error, :unsafe_entry} = error -> error
      _ -> {:error, :unreadable}
    end
  end

  defp physical_ancestors(root, parts) do
    Enum.reduce_while(parts, {:ok, root}, fn part, {:ok, parent} ->
      path = parent <> "/" <> part

      case File.lstat(path, time: :posix) do
        {:ok, %{type: :directory, access: access}} when access in [:read, :read_write] ->
          {:cont, {:ok, path}}

        {:ok, _} ->
          {:halt, {:error, :unsafe_entry}}

        {:error, _} ->
          {:halt, {:error, :unreadable}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp same?(%DateTime{} = stored, %DateTime{} = observed) do
    if DateTime.compare(stored, observed) == :eq,
      do: :ok,
      else: {:error, :source_changed}
  end

  defp same?(value, value), do: :ok
  defp same?(_, _), do: {:error, :source_changed}

  defp identity(stat), do: {stat.inode, stat.major_device, stat.minor_device}
end

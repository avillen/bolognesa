defmodule Bolognesa.Libraries.FfprobeMediaProbeTest do
  use ExUnit.Case, async: false

  alias Bolognesa.Libraries.Domain.{Library, MediaFile}
  alias Bolognesa.Libraries.Infrastructure.{BoundedCommand, FfprobeMediaProbe}

  setup do
    root = Path.join(System.tmp_dir!(), "probe-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    previous = Application.get_env(:bolognesa, :library_roots)
    Application.put_env(:bolognesa, :library_roots, [root])

    {:ok, canonical_root} =
      Bolognesa.Libraries.Infrastructure.LocalSourcePath.canonical_directory(root)

    on_exit(fn ->
      Application.put_env(:bolognesa, :library_roots, previous)
      File.rm_rf!(root)
    end)

    %{root: canonical_root}
  end

  test "passes an absolute path with spaces and dash prefix as one argument", %{root: root} do
    path = Path.join(root, "-my movie.mkv")
    File.write!(path, "video")
    executable = fake(root, "printf '{\"format\":{\"format_name\":\"matroska\"},\"streams\":[]}'")

    assert {:ok, %{format: "matroska"}} =
             FfprobeMediaProbe.inspect(library(root), file(path, root), executable: executable)
  end

  test "accepts the stored microsecond precision for an unchanged file", %{root: root} do
    path = Path.join(root, "unchanged.mkv")
    File.write!(path, "video")
    executable = fake(root, "printf '{\"format\":{\"format_name\":\"matroska\"},\"streams\":[]}'")
    observed = file(path, root)
    persisted = %{observed | modified_at: %{observed.modified_at | microsecond: {0, 6}}}

    assert {:ok, %{format: "matroska"}} =
             FfprobeMediaProbe.inspect(library(root), persisted, executable: executable)
  end

  test "suppresses tool diagnostics so successful JSON stays parseable", %{root: root} do
    path = Path.join(root, "diagnostic.mkv")
    File.write!(path, "video")

    executable =
      fake(
        root,
        "if [ \"$2\" != quiet ]; then printf diagnostic >&2; fi\nprintf '{\"format\":{\"format_name\":\"matroska\"},\"streams\":[]}'"
      )

    assert {:ok, %{format: "matroska"}} =
             FfprobeMediaProbe.inspect(library(root), file(path, root), executable: executable)
  end

  test "rejects descendant symlinks and changed observations", %{root: root} do
    target = Path.join(root, "target.mkv")
    File.write!(target, "video")
    File.ln_s!(target, Path.join(root, "link.mkv"))
    executable = fake(root, "printf '{\"format\":{},\"streams\":[]}'")

    assert {:error, :unsafe_entry} =
             FfprobeMediaProbe.inspect(library(root), file(Path.join(root, "link.mkv"), root),
               executable: executable
             )

    changed = %{file(target, root) | size_bytes: 1}

    assert {:error, :source_changed} =
             FfprobeMediaProbe.inspect(library(root), changed, executable: executable)
  end

  test "returns safe errors for tool failure, timeout and excess output", %{root: root} do
    assert {:error, :failed} = BoundedCommand.run(fake(root, "exit 7"), [], 5_000, 100)

    assert {:error, :too_large} =
             BoundedCommand.run(fake(root, "printf '123456789'"), [], 5_000, 3)

    assert {:error, :timeout} = BoundedCommand.run(fake(root, "sleep 1"), [], 10, 100)

    assert {:error, :tool_unavailable} =
             BoundedCommand.run(Path.join(root, "absent"), [], 100, 100)
  end

  test "passes non UTF-8 path bytes unchanged when supported by the runtime", %{root: root} do
    path = root <> "/" <> <<255, 46, 109, 107, 118>>
    executable = fake(root, "printf '{\"format\":{},\"streams\":[]}'")

    case File.write(path, "video") do
      :ok ->
        assert {:ok, %Bolognesa.Libraries.Domain.TechnicalMedia{}} =
                 FfprobeMediaProbe.inspect(library(root), file(path, root),
                   executable: executable
                 )

      {:error, :eilseq} ->
        observed = %MediaFile{
          relative_path: <<255, 46, 109, 107, 118>>,
          size_bytes: 5,
          modified_at: DateTime.utc_now()
        }

        assert {:error, :unreadable} =
                 FfprobeMediaProbe.inspect(library(root), observed, executable: executable)
    end
  end

  test "detects a file changed while ffprobe runs", %{root: root} do
    path = Path.join(root, "changing.mkv")
    File.write!(path, "video")
    executable = fake(root, "printf x >> '#{path}'\nprintf '{\"format\":{},\"streams\":[]}'")

    assert {:error, :source_changed} =
             FfprobeMediaProbe.inspect(library(root), file(path, root), executable: executable)
  end

  test "rejects a registered source redirected before probing", %{root: root} do
    source = Path.join(root, "registered")
    other = Path.join(root, "other")
    File.mkdir_p!(source)
    File.mkdir_p!(other)
    File.write!(Path.join(source, "movie.mkv"), "video")
    File.write!(Path.join(other, "movie.mkv"), "video")
    observed = file(Path.join(source, "movie.mkv"), source)
    File.rename!(source, source <> "-old")
    File.ln_s!(other, source)
    executable = fake(root, "printf '{\"format\":{},\"streams\":[]}'")

    assert {:error, :source_changed} =
             FfprobeMediaProbe.inspect(library(source), observed, executable: executable)
  end

  test "rejects a registered source with a redirected ancestor", %{root: root} do
    ancestor = Path.join(root, "ancestor")
    source = Path.join(ancestor, "registered")
    replacement = Path.join(root, "replacement")
    File.mkdir_p!(source)
    File.mkdir_p!(Path.join(replacement, "registered"))
    File.write!(Path.join(source, "movie.mkv"), "video")
    File.write!(Path.join(replacement, "registered/movie.mkv"), "video")
    observed = file(Path.join(source, "movie.mkv"), source)
    File.rename!(ancestor, ancestor <> "-old")
    File.ln_s!(replacement, ancestor)
    executable = fake(root, "printf '{\"format\":{},\"streams\":[]}'")

    assert {:error, :source_changed} =
             FfprobeMediaProbe.inspect(library(source), observed, executable: executable)
  end

  defp fake(root, body) do
    path = Path.join(root, "probe-#{System.unique_integer([:positive])}")
    File.write!(path, "#!/bin/sh\n#{body}\n")
    File.chmod!(path, 0o700)
    path
  end

  defp library(root), do: %Library{id: 1, name: "Test", path: root}

  defp file(path, root) do
    {:ok, stat} = File.stat(path, time: :posix)
    {:ok, modified_at} = DateTime.from_unix(stat.mtime)

    %MediaFile{
      relative_path: String.replace_prefix(path, root <> "/", ""),
      size_bytes: stat.size,
      modified_at: modified_at
    }
  end
end

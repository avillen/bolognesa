defmodule Bolognesa.Playback.LocalMediaFileTest do
  use ExUnit.Case, async: false

  alias Bolognesa.Playback.Infrastructure.LocalMediaFile
  alias Bolognesa.Libraries.Infrastructure.LocalSourcePath

  setup do
    base = hd(Application.fetch_env!(:bolognesa, :library_roots))
    File.mkdir_p!(base)
    directory = Path.join(base, "playback-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, directory: directory}
  end

  test "opens the validated original and permits bounded positional reads", %{
    directory: directory
  } do
    path = Path.join(directory, "film.mp4")
    File.write!(path, "abcdefgh")
    source = source(directory, "film.mp4")

    assert {:ok, %{device: device, size: 8}} = LocalMediaFile.open(source)
    assert {:ok, "cde"} = :file.pread(device, 2, 3)
    assert :ok = :file.close(device)
    assert File.read!(path) == "abcdefgh"
  end

  test "rejects traversal and null bytes before opening", %{directory: directory} do
    File.write!(Path.join(directory, "film.mp4"), "abcdefgh")
    valid = source(directory, "film.mp4")

    for relative_path <- ["../film.mp4", "/film.mp4", "./film.mp4", "film\0.mp4", "a//film.mp4"] do
      assert {:error, :unsafe_entry} =
               LocalMediaFile.open(%{valid | relative_path: relative_path})
    end
  end

  test "rejects a symlinked file and descendant directory", %{directory: directory} do
    File.mkdir_p!(Path.join(directory, "actual"))
    File.write!(Path.join(directory, "actual/film.mp4"), "abcdefgh")
    File.ln_s!("actual/film.mp4", Path.join(directory, "linked.mp4"))
    File.ln_s!("actual", Path.join(directory, "alias"))
    valid = source(directory, "actual/film.mp4")

    assert {:error, :unsafe_entry} = LocalMediaFile.open(%{valid | relative_path: "linked.mp4"})

    assert {:error, :unsafe_entry} =
             LocalMediaFile.open(%{valid | relative_path: "alias/film.mp4"})
  end

  test "rejects a redirected root and a changed file", %{directory: directory} do
    File.write!(Path.join(directory, "film.mp4"), "abcdefgh")
    valid = source(directory, "film.mp4")
    File.ln_s!(directory, Path.join(directory, "alias"))

    assert {:error, :source_changed} =
             LocalMediaFile.open(%{valid | path: Path.join(directory, "alias")})

    File.write!(Path.join(directory, "film.mp4"), "changed content")
    assert {:error, :source_changed} = LocalMediaFile.open(valid)
  end

  defp source(directory, relative_path) do
    {:ok, physical} = LocalSourcePath.canonical_directory(directory)
    {:ok, stat} = File.lstat(Path.join(physical, relative_path), time: :posix)
    {:ok, modified_at} = DateTime.from_unix(stat.mtime)

    %{
      path: physical,
      relative_path: relative_path,
      size_bytes: stat.size,
      modified_at: modified_at
    }
  end
end

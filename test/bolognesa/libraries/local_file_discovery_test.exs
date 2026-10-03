defmodule Bolognesa.Libraries.LocalFileDiscoveryTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Libraries.Infrastructure.{LocalFileDiscovery, LocalFileSource, LocalSourcePath}

  setup do
    root = Application.fetch_env!(:bolognesa, :library_roots) |> hd()
    path = Path.join(root, "discovery-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    %{path: path}
  end

  test "discovers candidates without changing their bytes", %{path: path} do
    File.write!(Path.join(path, "MOVIE.MP4"), "original")
    File.write!(Path.join(path, "cover.jpg"), "image")
    assert :ok = LocalFileDiscovery.walk(path, capture_sink())
    assert_receive {:entries, [entry]}
    assert entry.relative_path == "MOVIE.MP4"
    assert entry.size_bytes == 8

    assert entry.modified_at ==
             DateTime.from_unix!(File.stat!(Path.join(path, "MOVIE.MP4"), time: :posix).mtime)

    assert File.read!(Path.join(path, "MOVIE.MP4")) == "original"
    refute_receive {:entries, _}
  end

  test "finds every supported extension recursively and ignores other regular files", %{
    path: path
  } do
    extensions = ~w(mp4 m4v mkv avi mov webm mpeg mpg ts m2ts)
    File.mkdir_p!(Path.join(path, "nested/deeper"))

    expected =
      for extension <- extensions do
        name = "nested/deeper/movie.#{String.upcase(extension)}"
        File.write!(Path.join(path, name), extension)
        name
      end

    File.write!(Path.join(path, "movie.txt"), "ignored")
    assert :ok = LocalFileDiscovery.walk(path, capture_sink())
    assert_receive {:entries, entries}
    assert Enum.sort(Enum.map(entries, & &1.relative_path)) == Enum.sort(expected)
    refute_receive {:entries, _}
  end

  test "emits batches of 100, 100 and 1 for 201 candidates", %{path: path} do
    write_candidates(path, 201)
    assert :ok = LocalFileDiscovery.walk(path, capture_sink())
    assert_receive {:entries, first}
    assert_receive {:entries, second}
    assert_receive {:entries, last}
    assert [length(first), length(second), length(last)] == [100, 100, 1]
    assert Enum.uniq_by(first ++ second ++ last, & &1.relative_path) |> length() == 201
    refute_receive {:entries, _}
  end

  test "empty sources do not emit an empty batch", %{path: path} do
    assert :ok = LocalFileDiscovery.walk(path, capture_sink())
    refute_receive {:entries, _}
  end

  @tag skip:
         match?({:unix, :darwin}, :os.type()) &&
           "APFS rejects non UTF-8 filenames with :eilseq; exercised on Linux separately"
  test "preserves non UTF-8 filename bytes in discovery and shared H2a validation", %{path: path} do
    name = <<"movie-", 255, ".MP4">>
    File.write!(Path.join(path, name), "original")
    assert {:ok, canonical} = LocalFileSource.canonical_directory(path)
    assert {:ok, ^canonical} = LocalSourcePath.canonical_directory(path)
    assert :ok = LocalFileDiscovery.walk(path, capture_sink())
    assert_receive {:entries, [entry]}
    assert entry.relative_path == name
    assert File.read!(Path.join(path, name)) == "original"
  end

  test "rejects descendant links to directories inside and outside the source", %{path: path} do
    for target <- [path, System.tmp_dir!()] do
      link = Path.join(path, "link")
      File.ln_s!(target, link)
      assert {:error, :unsafe_entry} = LocalFileDiscovery.walk(path, capture_sink())
      File.rm!(link)
    end

    refute_receive {:entries, _}
  end

  test "rejects descendant links to regular files even with an ignored extension", %{path: path} do
    File.write!(Path.join(path, "original.txt"), "original")
    File.ln_s!(Path.join(path, "original.txt"), Path.join(path, "link.txt"))
    assert {:error, :unsafe_entry} = LocalFileDiscovery.walk(path, capture_sink())
    refute_receive {:entries, _}
  end

  test "rejects special files without trying to read their contents", %{path: path} do
    assert {_, 0} = System.cmd("mkfifo", [Path.join(path, "special.mp4")])
    assert {:error, :unsafe_entry} = LocalFileDiscovery.walk(path, capture_sink())
    refute_receive {:entries, _}
  end

  test "rejects missing and out-of-root sources before delivering entries", %{path: path} do
    assert {:error, :source_inaccessible} =
             LocalFileDiscovery.walk(path <> "/missing", capture_sink())

    assert {:error, :source_outside_roots} =
             LocalFileDiscovery.walk(System.tmp_dir!(), capture_sink())

    refute_receive {:entries, _}
  end

  test "rejects an inaccessible source", %{path: path} do
    File.chmod!(path, 0o000)

    try do
      assert {:error, :source_inaccessible} = LocalFileDiscovery.walk(path, capture_sink())
      refute_receive {:entries, _}
    after
      File.chmod!(path, 0o700)
    end
  end

  test "an unreadable descendant directory stops discovery", %{path: path} do
    nested = Path.join(path, "nested")
    File.mkdir_p!(nested)
    File.chmod!(nested, 0o000)

    try do
      assert {:error, :entry_unreadable} = LocalFileDiscovery.walk(path, capture_sink())
      refute_receive {:entries, _}
    after
      File.chmod!(nested, 0o700)
    end
  end

  test "an unreadable candidate stops discovery", %{path: path} do
    candidate = Path.join(path, "movie.mp4")
    File.write!(candidate, "original")
    File.chmod!(candidate, 0o000)

    try do
      assert {:error, :entry_unreadable} = LocalFileDiscovery.walk(path, capture_sink())
      refute_receive {:entries, _}
    after
      File.chmod!(candidate, 0o600)
    end
  end

  test "sink errors propagate immediately without delivering remaining batches", %{path: path} do
    write_candidates(path, 201)
    parent = self()

    for reason <- [:stale_attempt, :unavailable] do
      sink = fn entries ->
        send(parent, {:entries, entries})
        {:error, reason}
      end

      assert {:error, ^reason} = LocalFileDiscovery.walk(path, sink)
      assert_receive {:entries, entries}
      assert length(entries) == 100
      refute_receive {:entries, _}
    end
  end

  test "revalidates source accessibility after the final sink", %{path: path} do
    write_candidates(path, 1)

    try do
      sink = fn _ ->
        File.chmod!(path, 0o000)
        :ok
      end

      assert {:error, :source_inaccessible} = LocalFileDiscovery.walk(path, sink)
    after
      File.chmod!(path, 0o700)
    end
  end

  test "a renamed source cannot finish successfully", %{path: path} do
    write_candidates(path, 1)
    moved = path <> "-moved"

    try do
      sink = fn _ ->
        File.rename!(path, moved)
        :ok
      end

      assert {:error, :source_inaccessible} = LocalFileDiscovery.walk(path, sink)
    after
      File.rename(moved, path)
    end
  end

  test "a replacement source directory cannot finish successfully", %{path: path} do
    write_candidates(path, 1)
    moved = path <> "-moved"

    try do
      sink = fn _ ->
        File.rename!(path, moved)
        File.mkdir!(path)
        :ok
      end

      assert {:error, :source_changed} = LocalFileDiscovery.walk(path, sink)
    after
      File.rmdir(path)
      File.rename(moved, path)
    end
  end

  test "a source redirected by a link cannot finish successfully", %{path: path} do
    write_candidates(path, 1)
    moved = path <> "-moved"

    try do
      sink = fn _ ->
        File.rename!(path, moved)
        File.ln_s!(moved, path)
        :ok
      end

      assert {:error, :source_changed} = LocalFileDiscovery.walk(path, sink)
    after
      File.rm(path)
      File.rename(moved, path)
    end
  end

  test "a pending descendant replaced with a link stops without listing its target", %{path: path} do
    first = Path.join(path, "a-first")
    pending = Path.join(path, "z-pending")
    File.mkdir!(first)
    File.mkdir!(pending)
    write_candidates(first, 100)
    target = path <> "-target"
    File.mkdir!(target)
    File.write!(Path.join(target, "private.mp4"), "original")
    parent = self()

    try do
      sink = fn entries ->
        send(parent, {:entries, entries})
        File.rmdir!(pending)
        File.ln_s!(target, pending)
        :ok
      end

      assert {:error, :unsafe_entry} = LocalFileDiscovery.walk(path, sink)
      assert_receive {:entries, entries}
      assert length(entries) == 100
      assert Enum.all?(entries, &(:binary.match(&1.relative_path, "a-first/") == {0, 8}))
      refute_receive {:entries, _}
    after
      File.rm_rf!(target)
    end
  end

  test "rechecks descendant ancestors after a sink changes a directory already being traversed",
       %{path: path} do
    nested = Path.join(path, "nested")
    File.mkdir!(nested)
    write_candidates(nested, 101)
    moved = Path.join(path, "moved")
    parent = self()

    sink = fn entries ->
      send(parent, {:entries, entries})
      File.rename!(nested, moved)
      File.ln_s!(moved, nested)
      :ok
    end

    assert {:error, :unsafe_entry} = LocalFileDiscovery.walk(path, sink)
    assert_receive {:entries, entries}
    assert length(entries) == 100
    refute_receive {:entries, _}
  end

  test "rechecks descendant ancestors after the final partial sink", %{path: path} do
    nested = Path.join(path, "nested")
    moved = Path.join(path, "moved")
    File.mkdir!(nested)
    write_candidates(nested, 1)

    sink = fn _ ->
      File.rename!(nested, moved)
      File.ln_s!(moved, nested)
      :ok
    end

    assert {:error, :unsafe_entry} = LocalFileDiscovery.walk(path, sink)
  end

  test "rechecks physical ancestors above the source after the final sink", %{path: path} do
    parent = Path.join(path, "parent")
    source = Path.join(parent, "source")
    moved = Path.join(path, "moved")
    File.mkdir_p!(source)
    write_candidates(source, 1)

    sink = fn _ ->
      File.rename!(parent, moved)
      File.ln_s!(moved, parent)
      :ok
    end

    assert {:error, :source_changed} = LocalFileDiscovery.walk(source, sink)
  end

  defp capture_sink do
    parent = self()

    fn entries ->
      send(parent, {:entries, entries})
      :ok
    end
  end

  defp write_candidates(path, count) do
    for number <- 1..count do
      File.write!(Path.join(path, "movie-#{number}.mp4"), "original")
    end
  end
end

defmodule Bolognesa.Libraries.Infrastructure.Services.LocalFileDiscovery do
  @moduledoc """
  Discovers physical candidates without writing to the source.

  Checks source identity and physical ancestors between filesystem operations and
  after each sink. These checks detect replacements observed by the walk; File
  APIs do not provide an atomic snapshot against concurrent filesystem changes.
  """
  @behaviour Bolognesa.Libraries.Application.Ports.Services.FileDiscovery

  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Libraries.Domain.NewMediaFile

  @batch_size Bolognesa.Libraries.Infrastructure.Jobs.ScanPolicy.batch_size()
  @extensions ~w(.mp4 .m4v .mkv .avi .mov .webm .mpeg .mpg .ts .m2ts)

  @impl true
  def walk(path, sink) do
    with {:ok, root} <- LocalSourcePath.canonical_directory(path),
         :ok <- same_identity(path, root),
         {:ok, stat} <- source_stat(root),
         source = %{root: root, identity: identity(stat)},
         {:ok, entries} <- list_directory(source, ""),
         :ok <- traverse(source, [{"", entries}], [], 0, sink) do
      revalidate_source(path, source)
    end
  end

  defp traverse(source, [], batch, _count, sink), do: emit_batch(source, batch, sink)

  defp traverse(source, [{directory, []} | stack], batch, count, sink) do
    with :ok <- check_directory(source, directory) do
      traverse(source, stack, batch, count, sink)
    end
  end

  defp traverse(source, [{directory, [name | names]} | stack], batch, count, sink) do
    relative_path = join_relative(directory, name)
    remaining = [{directory, names} | stack]

    with :ok <- check_directory(source, directory),
         {:ok, stat} <- entry_stat(absolute_path(source, relative_path)) do
      visit(source, relative_path, stat, remaining, batch, count, sink)
    end
  end

  defp visit(source, path, %{type: :directory}, stack, batch, count, sink) do
    with {:ok, entries} <- list_directory(source, path) do
      traverse(source, [{path, entries} | stack], batch, count, sink)
    end
  end

  defp visit(source, path, %{type: :regular} = stat, stack, batch, count, sink) do
    if ascii_lower(Path.extname(path)) in @extensions,
      do: add_candidate(source, path, stat, stack, batch, count, sink),
      else: traverse(source, stack, batch, count, sink)
  end

  defp visit(_source, _path, _stat, _stack, _batch, _count, _sink),
    do: {:error, :unsafe_entry}

  defp add_candidate(source, path, stat, stack, batch, count, sink) do
    with :ok <- readable_entry(stat),
         {:ok, modified_at} <- DateTime.from_unix(stat.mtime),
         {:ok, entry} <-
           NewMediaFile.new(%{
             relative_path: path,
             size_bytes: stat.size,
             modified_at: modified_at
           }) do
      continue_batch(source, stack, [entry | batch], count + 1, sink)
    else
      _ -> {:error, :entry_unreadable}
    end
  end

  defp continue_batch(source, stack, batch, @batch_size, sink) do
    with :ok <- emit_batch(source, batch, sink) do
      traverse(source, stack, [], 0, sink)
    end
  end

  defp continue_batch(source, stack, batch, count, sink),
    do: traverse(source, stack, batch, count, sink)

  defp emit_batch(_source, [], _sink), do: :ok

  defp emit_batch(source, batch, sink) do
    with :ok <- sink.(Enum.reverse(batch)) do
      Enum.reduce_while(batch, :ok, fn entry, :ok ->
        continue_check(check_directory(source, relative_parent(entry.relative_path)))
      end)
    end
  end

  defp list_directory(source, directory) do
    with :ok <- check_directory(source, directory),
         {:ok, names} <- :file.list_dir_all(absolute_path(source, directory)) do
      {:ok, names |> Enum.map(&IO.chardata_to_string/1) |> Enum.sort()}
    else
      {:error, reason} when reason in [:source_changed, :source_inaccessible, :unsafe_entry] ->
        {:error, reason}

      {:error, _} ->
        {:error, :entry_unreadable}
    end
  end

  defp check_directory(source, relative_path) do
    with :ok <- check_source_ancestors(source.root),
         {:ok, stat} <- source_stat(source.root),
         :ok <- same_identity(source.identity, identity(stat)) do
      check_descendant_ancestors(source, relative_path)
    end
  end

  defp check_source_ancestors(root) do
    Enum.reduce_while(ancestor_paths(root), :ok, fn path, :ok ->
      continue_check(check_physical_directory(path, :source_changed, :source_inaccessible))
    end)
  end

  defp check_descendant_ancestors(_source, ""), do: :ok

  defp check_descendant_ancestors(source, relative_path) do
    Enum.reduce_while(ancestor_paths(relative_path), :ok, fn path, :ok ->
      continue_check(
        check_physical_directory(absolute_path(source, path), :unsafe_entry, :entry_unreadable)
      )
    end)
  end

  defp check_physical_directory(path, unsafe_reason, unreadable_reason) do
    case File.lstat(path, time: :posix) do
      {:ok, %{type: :directory, access: access}} when access in [:read, :read_write] -> :ok
      {:ok, %{type: :directory}} -> {:error, unreadable_reason}
      {:ok, _} -> {:error, unsafe_reason}
      {:error, _} -> {:error, unreadable_reason}
    end
  end

  defp source_stat(root) do
    case File.stat(root, time: :posix) do
      {:ok, stat} -> {:ok, stat}
      {:error, _} -> {:error, :source_inaccessible}
    end
  end

  defp entry_stat(path) do
    case File.lstat(path, time: :posix) do
      {:ok, stat} -> {:ok, stat}
      {:error, _} -> {:error, :entry_unreadable}
    end
  end

  defp revalidate_source(path, source) do
    with {:ok, root} <- LocalSourcePath.canonical_directory(path),
         :ok <- same_identity(source.root, root) do
      check_directory(source, "")
    end
  end

  defp readable_entry(%{access: access}) when access in [:read, :read_write], do: :ok
  defp readable_entry(_), do: {:error, :entry_unreadable}

  defp same_identity(identity, identity), do: :ok
  defp same_identity(_, _), do: {:error, :source_changed}

  defp identity(stat), do: {stat.inode, stat.major_device, stat.minor_device}

  defp ancestor_paths(path) do
    path |> Path.split() |> Enum.scan(&Path.join(&2, &1))
  end

  defp absolute_path(source, ""), do: source.root
  defp absolute_path(source, path), do: source.root <> "/" <> path

  defp join_relative("", name), do: name
  defp join_relative(directory, name), do: directory <> "/" <> name

  defp relative_parent(path) do
    case Path.dirname(path) do
      "." -> ""
      directory -> directory
    end
  end

  defp continue_check(:ok), do: {:cont, :ok}
  defp continue_check({:error, _} = error), do: {:halt, error}

  defp ascii_lower(binary) do
    for <<byte <- binary>>, into: <<>> do
      <<if(byte in ?A..?Z, do: byte + 32, else: byte)>>
    end
  end
end

defmodule Bolognesa.Playback.Infrastructure.LocalMediaFile do
  @moduledoc "Open a validated movie file for bounded positional reads."

  require Record
  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Playback.Domain.ReadModels.Source

  @type opened :: %{device: IO.device(), size: non_neg_integer()}
  @type failure :: :source_inaccessible | :source_changed | :unsafe_entry | :unreadable

  @type file_access :: atom()

  @spec open(Source.t(), file_access()) ::
          {:ok, opened()} | {:error, failure()}
  def open(source, file_access \\ File) do
    with {:ok, root_identity} <- check_root(source.path),
         :ok <- safe_relative_path(source.relative_path),
         {:ok, ancestor_identities} <-
           relative_ancestors(source.path, source.relative_path, file_access),
         path = source.path <> "/" <> source.relative_path,
         {:ok, before_stat} <- regular_file(path, source, file_access),
         {:ok, device} <- open_file(path) do
      validate_device(
        device,
        before_stat,
        source,
        root_identity,
        ancestor_identities,
        file_access
      )
    end
  end

  defp check_root(path) do
    with {:ok, physical} <- LocalSourcePath.canonical_directory(path),
         true <- physical == path,
         :ok <- physical_ancestors(path),
         {:ok, stat} <- File.stat(path, time: :posix) do
      {:ok, identity(stat)}
    else
      false -> {:error, :source_changed}
      _ -> {:error, :source_inaccessible}
    end
  end

  defp safe_relative_path(path) when is_binary(path) do
    parts = :binary.split(path, "/", [:global])

    if :binary.match(path, <<0>>) != :nomatch or
         Enum.any?(parts, &(&1 in ["", ".", ".."])),
       do: {:error, :unsafe_entry},
       else: :ok
  end

  defp safe_relative_path(_), do: {:error, :unsafe_entry}

  defp physical_ancestors(path) do
    parts = Path.split(path) |> Enum.reject(&(&1 == "/"))
    check_directory_chain("", parts)
  end

  defp relative_ancestors(root, relative_path, file_access) do
    parts = :binary.split(relative_path, "/", [:global]) |> Enum.drop(-1)

    Enum.reduce_while(parts, {root, []}, fn part, {parent, identities} ->
      path = parent <> "/" <> part

      case file_access.lstat(path, time: :posix) do
        {:ok, %{type: :directory, access: access} = stat}
        when access in [:read, :read_write] ->
          {:cont, {path, [identity(stat) | identities]}}

        {:ok, _} ->
          {:halt, {:error, :unsafe_entry}}

        {:error, _} ->
          {:halt, {:error, :source_inaccessible}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      {_, identities} -> {:ok, Enum.reverse(identities)}
    end
  end

  defp check_directory_chain(root, parts) do
    Enum.reduce_while(parts, root, fn part, parent ->
      path = parent <> "/" <> part

      case File.lstat(path, time: :posix) do
        {:ok, %{type: :directory, access: access}} when access in [:read, :read_write] ->
          {:cont, path}

        {:ok, _} ->
          {:halt, {:error, :unsafe_entry}}

        {:error, _} ->
          {:halt, {:error, :source_inaccessible}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  defp regular_file(path, source, file_access) do
    with {:ok, %{type: :regular, access: access} = stat} <-
           file_access.lstat(path, time: :posix),
         true <- access in [:read, :read_write],
         {:ok, modified_at} <- DateTime.from_unix(stat.mtime),
         true <-
           stat.size == source.size_bytes and
             DateTime.compare(modified_at, source.modified_at) == :eq do
      {:ok, stat}
    else
      {:ok, _} -> {:error, :unsafe_entry}
      false -> {:error, :source_changed}
      _ -> {:error, :unreadable}
    end
  end

  defp open_file(path) do
    case :file.open(path, [:read, :binary, :raw]) do
      {:ok, device} -> {:ok, device}
      {:error, _} -> {:error, :unreadable}
    end
  end

  defp validate_device(
         device,
         before_stat,
         source,
         root_identity,
         ancestor_identities,
         file_access
       ) do
    result =
      with {:ok, info} <- :file.read_file_info(device, time: :posix),
           true <- file_info(info, :type) == :regular,
           true <- file_info(info, :size) == before_stat.size,
           true <- file_info(info, :mtime) == before_stat.mtime,
           true <- device_identity(info) == identity(before_stat),
           {:ok, after_root_identity} <- check_root(source.path),
           true <- after_root_identity == root_identity,
           {:ok, after_ancestor_identities} <-
             relative_ancestors(source.path, source.relative_path, file_access),
           true <- after_ancestor_identities == ancestor_identities do
        :ok
      else
        {:error, _} = error -> error
        false -> {:error, :source_changed}
      end

    case result do
      :ok ->
        {:ok, %{device: device, size: before_stat.size}}

      {:error, _} = error ->
        :file.close(device)
        error
    end
  end

  defp identity(stat), do: {stat.inode, stat.major_device, stat.minor_device}

  defp device_identity(info) do
    {file_info(info, :inode), file_info(info, :major_device), file_info(info, :minor_device)}
  end
end

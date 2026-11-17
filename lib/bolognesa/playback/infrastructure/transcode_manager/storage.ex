defmodule Bolognesa.Playback.Infrastructure.TranscodeManager.Storage do
  @moduledoc "Private temporary session directories, kept outside every media library."
  alias Bolognesa.Infrastructure.LocalSourcePath

  @max_bytes 512 * 1_024 * 1_024

  @type failure :: :unsafe_root | :storage_unavailable

  @spec root() :: {:ok, Path.t()} | {:error, failure()}
  def root do
    path = configured_path()
    expanded = Path.expand(path)

    if Path.type(path) != :absolute or inside_library?(expanded, library_directories()) do
      {:error, :unsafe_root}
    else
      ensure_root(expanded)
    end
  end

  @spec create_session_directory(Path.t(), String.t()) ::
          {:ok, Path.t()} | {:error, :storage_unavailable}
  def create_session_directory(root, id) do
    directory = Path.join(root, "session-#{id}")

    with :ok <- File.mkdir(directory),
         :ok <- secure(directory) do
      {:ok, directory}
    else
      {:error, _} -> {:error, :storage_unavailable}
    end
  end

  @spec remove_abandoned(Path.t()) :: :ok
  def remove_abandoned(root) do
    case File.ls(root) do
      {:ok, names} -> Enum.each(names, &remove_if_session(root, &1))
      _ -> :ok
    end
  end

  @doc "An unreadable directory counts as over the limit."
  @spec over_limit?(Path.t()) :: boolean()
  def over_limit?(directory), do: bytes(directory) > @max_bytes

  defp configured_path do
    Application.get_env(
      :bolognesa,
      :transcode_root,
      Path.join(System.tmp_dir!(), "bolognesa-transcode")
    )
  end

  defp library_directories do
    Application.fetch_env!(:bolognesa, :library_roots)
    |> Enum.map(&resolve_library_directory/1)
  end

  defp resolve_library_directory(library) do
    case LocalSourcePath.canonical_directory(library) do
      {:ok, physical} -> physical
      _ -> Path.expand(library)
    end
  end

  defp ensure_root(expanded) do
    case File.mkdir_p(expanded) do
      :ok -> verify_outside_libraries(expanded)
      {:error, _} -> {:error, :storage_unavailable}
    end
  end

  defp verify_outside_libraries(expanded) do
    case LocalSourcePath.canonical_directory(expanded) do
      {:error, :source_outside_roots} -> {:ok, expanded}
      _ -> {:error, :unsafe_root}
    end
  end

  defp inside_library?(path, libraries) do
    Enum.any?(libraries, fn library ->
      path == library or String.starts_with?(path, library <> "/")
    end)
  end

  defp secure(directory) do
    case File.chmod(directory, 0o700) do
      :ok ->
        :ok

      {:error, reason} ->
        File.rm_rf(directory)
        {:error, reason}
    end
  end

  defp remove_if_session(root, name) do
    if Regex.match?(~r/\Asession-[0-9a-f-]{36}\z/, name) do
      File.rm_rf(Path.join(root, name))
    end
  end

  defp bytes(directory) do
    directory
    |> File.ls!()
    |> Enum.reduce(0, fn name, total ->
      case File.stat(Path.join(directory, name)) do
        {:ok, %{type: :regular, size: size}} -> total + size
        _ -> total
      end
    end)
  rescue
    _ -> @max_bytes + 1
  end
end

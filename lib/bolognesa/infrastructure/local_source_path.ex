defmodule Bolognesa.Infrastructure.LocalSourcePath do
  @moduledoc false

  @spec canonical_directory(String.t()) ::
          {:ok, String.t()} | {:error, :source_inaccessible | :source_outside_roots}
  def canonical_directory(path) do
    with {:ok, physical_path} <- real_path(path),
         :ok <- allowed?(physical_path),
         :ok <- readable?(physical_path) do
      {:ok, physical_path}
    end
  end

  defp real_path(path) do
    resolve(Path.expand(path), 0)
  end

  defp resolve(_path, depth) when depth > 40, do: {:error, :source_inaccessible}

  defp resolve(path, depth) do
    components = Path.split(path) |> tl()

    result =
      Enum.reduce_while(components, "/", fn component, parent ->
        candidate = Path.join(parent, component)

        case File.read_link(candidate) do
          {:ok, target} ->
            remaining = Enum.drop(components, length(Path.split(candidate)) - 1)
            expanded = Path.expand(target, parent)
            {:halt, {:link, Path.join([expanded | remaining])}}

          {:error, :einval} ->
            {:cont, candidate}

          {:error, _} ->
            {:halt, :missing}
        end
      end)

    case result do
      {:link, target} -> resolve(target, depth + 1)
      :missing -> {:error, :source_inaccessible}
      resolved -> {:ok, resolved}
    end
  end

  defp allowed?(path) do
    roots = Application.get_env(:bolognesa, :library_roots, [])

    if Enum.any?(roots, &allowed_root?(&1, path)),
      do: :ok,
      else: {:error, :source_outside_roots}
  end

  defp allowed_root?(root, path) do
    case real_path(root) do
      {:ok, physical_root} ->
        path == physical_root or String.starts_with?(path, physical_root <> "/")

      _ ->
        false
    end
  end

  defp readable?(path) do
    if File.dir?(path) and match?({:ok, _}, :file.list_dir_all(path)) and
         match?({:ok, _}, File.stat(Path.join(path, "."))),
       do: :ok,
       else: {:error, :source_inaccessible}
  end
end

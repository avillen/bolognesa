defmodule Bolognesa.Libraries.Infrastructure.Repositories.EctoLibraryRepository do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Repositories.LibraryRepository

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoLibraryRepository.LibraryMapper
  alias Bolognesa.Repo

  @impl true
  def insert(details) do
    %LibrarySchema{}
    |> LibrarySchema.changeset(%{
      name: details.name,
      path: details.path,
      content_type: details.content_type
    })
    |> Repo.insert(log: false)
    |> case do
      {:ok, stored} -> {:ok, LibraryMapper.to_library(stored)}
      {:error, changeset} -> {:error, map_error(changeset)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  @impl true
  def list do
    libraries = Repo.all(from_library_query())
    {:ok, Enum.map(libraries, &LibraryMapper.to_library/1)}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  defp from_library_query do
    import Ecto.Query
    from library in LibrarySchema, order_by: [asc: library.name, asc: library.id]
  end

  defp map_error(changeset) do
    if Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
         opts[:constraint] == :unique and opts[:constraint_name] == "libraries_path_index"
       end), do: :duplicate_source, else: :unavailable
  end
end

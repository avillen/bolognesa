defmodule Bolognesa.Libraries do
  @moduledoc "Configure and read media libraries."
  alias Bolognesa.Libraries.Application.{CreateLibrary, ListLibraries}
  alias Bolognesa.Libraries.Domain.{Library, NewLibrary}
  alias Bolognesa.Libraries.Infrastructure.LocalFileSource
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository
  alias Bolognesa.Identity.Domain.Actor

  @spec create_library(Actor.t() | nil, NewLibrary.attrs()) ::
          {:ok, Library.t()}
          | {:error,
             NewLibrary.error()
             | :forbidden
             | :duplicate_source
             | :source_inaccessible
             | :source_outside_roots
             | :unavailable}
  def create_library(actor, attrs),
    do: CreateLibrary.call(actor, attrs, EctoLibraryRepository, LocalFileSource)

  @spec list_libraries(Actor.t() | nil) ::
          {:ok, [Library.t()]} | {:error, :forbidden | :unavailable}
  def list_libraries(actor), do: ListLibraries.call(actor, EctoLibraryRepository)
end

defmodule Bolognesa.Libraries.Application.UseCases.CreateLibrary do
  @moduledoc "Authorize and register one library source."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Libraries.Application.Ports.{FileSource, LibraryRepository}
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewLibrary

  @spec call(
          Actor.t(),
          NewLibrary.attrs(),
          LibraryRepository.adapter(),
          FileSource.adapter()
        ) ::
          {:ok, Library.t()}
          | {:error,
             NewLibrary.error()
             | :forbidden
             | :duplicate_source
             | :source_inaccessible
             | :source_outside_roots
             | :unavailable}
  def call(actor, attrs, repository, file_source) do
    with :ok <- Identity.authorize(actor, :admin),
         {:ok, details} <- NewLibrary.new(attrs),
         {:ok, canonical_path} <- file_source.canonical_directory(details.path) do
      repository.insert(%{details | path: canonical_path})
    end
  end
end

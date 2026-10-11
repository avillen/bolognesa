defmodule Bolognesa.Libraries.Infrastructure.Repositories.EctoLibraryRepository.LibraryMapper do
  @moduledoc false
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Libraries.Domain.Library

  @spec to_library(LibrarySchema.t()) :: Library.t()
  def to_library(schema),
    do: %Library{
      id: schema.id,
      name: schema.name,
      path: schema.path,
      content_type: schema.content_type
    }
end

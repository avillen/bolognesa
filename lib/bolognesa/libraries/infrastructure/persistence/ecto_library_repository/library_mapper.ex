defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibraryMapper do
  @moduledoc false
  alias Bolognesa.Libraries.Domain.Library
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema

  @spec to_library(LibrarySchema.t()) :: Library.t()
  def to_library(schema), do: %Library{id: schema.id, name: schema.name, path: schema.path}
end

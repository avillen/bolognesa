defmodule Bolognesa.Libraries.Application.Ports.Repositories.LibraryRepository do
  @moduledoc "Persistence needed to configure libraries."
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewLibrary
  @type adapter :: module()
  @callback insert(NewLibrary.t()) ::
              {:ok, Library.t()} | {:error, :duplicate_source | :unavailable}
  @callback list() :: {:ok, [Library.t()]} | {:error, :unavailable}
end

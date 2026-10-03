defmodule Bolognesa.Libraries.Application.Ports.LibraryRepository do
  @moduledoc "Persistence needed to configure libraries."
  alias Bolognesa.Libraries.Domain.{Library, NewLibrary}
  @type adapter :: atom()
  @callback insert(NewLibrary.t()) ::
              {:ok, Library.t()} | {:error, :duplicate_source | :unavailable}
  @callback list() :: {:ok, [Library.t()]} | {:error, :unavailable}
end

defmodule Bolognesa.Libraries.Application.ListLibraries do
  @moduledoc "Authorize and list configured libraries."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Libraries.Application.Ports.LibraryRepository
  alias Bolognesa.Libraries.Domain.Library

  @spec call(Actor.t() | nil, LibraryRepository.adapter()) ::
          {:ok, [Library.t()]} | {:error, :forbidden | :unavailable}
  def call(actor, repository) do
    with :ok <- Identity.authorize(actor, :admin), do: repository.list()
  end
end

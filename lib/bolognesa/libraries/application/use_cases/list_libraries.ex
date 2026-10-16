defmodule Bolognesa.Libraries.Application.UseCases.ListLibraries do
  @moduledoc "Authorize and list configured libraries."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Libraries.Application.Ports.Repositories.LibraryRepository
  alias Bolognesa.Libraries.Domain.Entities.Library

  @spec call(Actor.t(), LibraryRepository.adapter()) ::
          {:ok, [Library.t()]} | {:error, :forbidden | :unavailable}
  def call(actor, repository) do
    with :ok <- Accounts.authorize(actor, :admin), do: repository.list()
  end
end

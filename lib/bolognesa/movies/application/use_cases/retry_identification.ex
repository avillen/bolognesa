defmodule Bolognesa.Movies.Application.UseCases.RetryIdentification do
  @moduledoc "Request a new automatic identification unless a manual choice owns the file."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Movies.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Movies.Domain.Entities.Identification

  @spec call(Actor.t(), pos_integer(), IdentificationRepository.adapter()) ::
          {:ok, Identification.t()}
          | {:error,
             :forbidden | :not_found | :unavailable | :wrong_content_type | :manual_locked}
  def call(actor, file_id, repository) do
    with :ok <- Accounts.authorize(actor, :admin) do
      repository.retry(file_id)
    end
  end
end

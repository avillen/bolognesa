defmodule Bolognesa.Series.Application.UseCases.RetryIdentification do
  @moduledoc "Request a new automatic identification unless a manual choice owns the file."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Series.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Series.Domain.Entities.Identification

  @spec call(Actor.t(), pos_integer(), IdentificationRepository.adapter()) ::
          {:ok, Identification.t()}
          | {:error,
             :forbidden | :not_found | :unavailable | :wrong_content_type | :manual_locked}
  def call(actor, file_id, repository) do
    with :ok <- Identity.authorize(actor, :admin) do
      repository.retry(file_id)
    end
  end
end

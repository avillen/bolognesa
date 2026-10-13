defmodule Bolognesa.Music.Application.UseCases.RetryImport do
  @moduledoc "Authorize explicit retry of a local music import."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Music.Application.Ports.Repositories.ImportRepository
  @type result :: :ok | {:error, :forbidden | :not_found | :unavailable}
  @spec call(Actor.t() | nil, pos_integer(), ImportRepository.adapter()) :: result()
  def call(actor, file_id, repository) do
    with :ok <- Identity.authorize(actor, :admin), true <- is_integer(file_id) and file_id > 0 do
      repository.request_retry(file_id)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end
end

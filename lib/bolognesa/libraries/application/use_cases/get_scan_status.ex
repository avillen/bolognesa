defmodule Bolognesa.Libraries.Application.UseCases.GetScanStatus do
  @moduledoc "Authorize a library scan status query."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus

  @spec call(Actor.t(), Library.id(), ScanRepository.adapter()) ::
          {:ok, ScanStatus.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, library_id, repository) do
    with :ok <- Identity.authorize(actor, :admin) do
      repository.status(library_id)
    end
  end
end

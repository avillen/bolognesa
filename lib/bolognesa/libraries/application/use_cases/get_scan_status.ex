defmodule Bolognesa.Libraries.Application.UseCases.GetScanStatus do
  @moduledoc "Authorize a library scan status query."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus

  @spec call(AuthenticatedUser.t(), Library.id(), ScanRepository.adapter()) ::
          {:ok, ScanStatus.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, library_id, repository) do
    with :ok <- Accounts.authorize(actor, :admin) do
      repository.status(library_id)
    end
  end
end

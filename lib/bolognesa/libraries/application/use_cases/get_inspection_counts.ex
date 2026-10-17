defmodule Bolognesa.Libraries.Application.UseCases.GetInspectionCounts do
  @moduledoc "Authorize aggregate technical inspection counts for one library."

  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.InspectionCounts

  @spec call(AuthenticatedUser.t(), Library.id(), InspectionRepository.adapter()) ::
          {:ok, InspectionCounts.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, library_id, repository) do
    with :ok <- Accounts.authorize(actor, :admin) do
      repository.counts(library_id)
    end
  end
end

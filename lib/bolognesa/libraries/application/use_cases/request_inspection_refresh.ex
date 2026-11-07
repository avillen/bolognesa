defmodule Bolognesa.Libraries.Application.UseCases.RequestInspectionRefresh do
  @moduledoc "Authorize an explicit refresh of current video inspection facts."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository
  alias Bolognesa.Libraries.Domain.Entities.MediaFile

  @spec call(
          AuthenticatedUser.t() | nil,
          MediaFile.id(),
          pos_integer(),
          InspectionRepository.adapter()
        ) ::
          InspectionRepository.refresh_result() | {:error, :forbidden}
  def call(actor, file_id, expected_revision, repository) do
    with :ok <- Accounts.authorize(actor, :admin) do
      repository.request_refresh(file_id, expected_revision, DateTime.utc_now())
    end
  end
end

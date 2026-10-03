defmodule Bolognesa.Libraries.Application.GetScanStatus do
  @moduledoc "Authorize a library scan status query."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Libraries.Application.Ports.ScanRepository
  alias Bolognesa.Libraries.Domain.{Library, ScanStatus}

  @spec call(Actor.t() | nil, Library.id(), ScanRepository.adapter()) ::
          {:ok, ScanStatus.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, library_id, repository) do
    with :ok <- Identity.authorize(actor, :admin) do
      repository.status(library_id)
    end
  end
end

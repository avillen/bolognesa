defmodule Bolognesa.Libraries.Application.StartScan do
  @moduledoc "Authorize a library scan request."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Libraries.Application.Ports.ScanRepository
  alias Bolognesa.Libraries.Domain.{Library, Scan}

  @spec call(Actor.t() | nil, Library.id(), ScanRepository.adapter()) ::
          {:ok, Scan.t()} | {:error, :forbidden | :not_found | :scan_in_progress | :unavailable}
  def call(actor, library_id, repository) do
    with :ok <- Identity.authorize(actor, :admin) do
      repository.request(library_id)
    end
  end
end

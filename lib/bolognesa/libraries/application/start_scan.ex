defmodule Bolognesa.Libraries.Application.StartScan do
  @moduledoc "Authorize a library scan request."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Libraries.Application.Ports.ScanRepository
  alias Bolognesa.Libraries.Domain.{Library, Scan}

  @spec call(Actor.t(), Library.id(), ScanRepository.adapter(), keyword()) ::
          {:ok, Scan.t()} | {:error, :forbidden | :not_found | :scan_in_progress | :unavailable}
  def call(actor, library_id, repository, opts \\ []) do
    with :ok <- Identity.authorize(actor, :admin) do
      repository.request(library_id, Keyword.get(opts, :force_inspection?, false))
    end
  end
end

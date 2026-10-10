defmodule Bolognesa.Libraries.Application.GetInspectionCounts do
  @moduledoc "Authorize aggregate technical inspection counts for one library."

  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Libraries.Domain.{InspectionCounts, Library}

  @spec call(Actor.t(), Library.id(), module()) ::
          {:ok, InspectionCounts.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, library_id, repository) do
    with :ok <- Identity.authorize(actor, :admin) do
      repository.counts(library_id)
    end
  end
end

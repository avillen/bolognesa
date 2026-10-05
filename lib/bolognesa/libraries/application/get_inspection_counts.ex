defmodule Bolognesa.Libraries.Application.GetInspectionCounts do
  @moduledoc "Authorize aggregate technical inspection counts for one library."

  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Libraries.Domain.Library

  @spec call(Actor.t() | nil, Library.id(), module()) ::
          {:ok, map()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, library_id, repository) do
    with :ok <- Identity.authorize(actor, :admin) do
      repository.counts(library_id)
    end
  end
end

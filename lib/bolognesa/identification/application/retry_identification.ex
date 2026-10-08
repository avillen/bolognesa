defmodule Bolognesa.Identification.Application.RetryIdentification do
  @moduledoc "Request a new automatic identification unless a manual choice owns the file."
  alias Bolognesa.Identity

  def call(actor, file_id, repository) do
    with :ok <- Identity.authorize(actor, :admin) do
      repository.retry(file_id)
    end
  end
end

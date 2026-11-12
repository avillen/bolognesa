defmodule Bolognesa.Movies.Infrastructure.Jobs.Oban.ObanIdentificationJob do
  @moduledoc "Adds a durable identification job to the caller's transaction."

  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Movies.Infrastructure.Jobs.Workers.IdentificationWorker

  @spec insert(Ecto.Multi.t(), MovieIdentificationSchema.t()) :: Ecto.Multi.t()
  def insert(multi, decision) do
    Oban.insert(
      multi,
      :job,
      IdentificationWorker.new(%{file_id: decision.media_file_id, token: decision.token}),
      log: false
    )
  end
end

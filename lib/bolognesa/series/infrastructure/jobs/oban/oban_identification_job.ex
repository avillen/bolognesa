defmodule Bolognesa.Series.Infrastructure.Jobs.Oban.ObanIdentificationJob do
  @moduledoc "Adds a durable identification job to the caller's transaction."

  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Series.Infrastructure.Jobs.Workers.IdentificationWorker

  @spec insert(Ecto.Multi.t(), SeriesIdentificationSchema.t()) :: Ecto.Multi.t()
  def insert(multi, decision) do
    Oban.insert(
      multi,
      :job,
      IdentificationWorker.new(%{file_id: decision.media_file_id, token: decision.token}),
      log: false
    )
  end
end

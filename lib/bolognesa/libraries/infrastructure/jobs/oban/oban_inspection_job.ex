defmodule Bolognesa.Libraries.Infrastructure.Jobs.Oban.ObanInspectionJob do
  @moduledoc "Inserts an inspection job within the caller's transaction."

  alias Bolognesa.Libraries.Infrastructure.Jobs.Workers.InspectionWorker
  alias Bolognesa.Repo

  @spec insert!(pos_integer(), Ecto.UUID.t()) :: Oban.Job.t()
  def insert!(file_id, token) do
    case Oban.insert(InspectionWorker.new(%{media_file_id: file_id, token: token})) do
      {:ok, job} -> job
      {:error, _changeset} -> Repo.rollback(:unavailable)
    end
  end
end

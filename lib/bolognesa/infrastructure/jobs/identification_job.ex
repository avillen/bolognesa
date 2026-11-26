defmodule Bolognesa.Infrastructure.Jobs.IdentificationJob do
  @moduledoc "Inserts and runs token-protected identification jobs for a content context."

  alias Bolognesa.Infrastructure.Observability.Events

  @spec insert(
          Ecto.Multi.t(),
          module(),
          %{:media_file_id => pos_integer(), :token => String.t(), optional(atom()) => any()}
        ) :: Ecto.Multi.t()
  def insert(multi, worker, decision) do
    Oban.insert(
      multi,
      :job,
      worker.new(%{file_id: decision.media_file_id, token: decision.token}),
      log: false
    )
  end

  @spec perform(Oban.Job.t(), atom(), (pos_integer(), String.t(), pos_integer() -> result)) ::
          result | {:error, :unexpected_failure} | {:cancel, :invalid_job}
        when result: term()
  def perform(
        %Oban.Job{args: %{"file_id" => id, "token" => token}, attempt: attempt} = job,
        context,
        identify
      )
      when is_integer(id) and id > 0 and is_binary(token) do
    identify.(id, token, attempt)
  rescue
    _ -> unexpected_failure(context, id, job.id, attempt)
  catch
    _, _ -> unexpected_failure(context, id, job.id, attempt)
  end

  def perform(_, _, _), do: {:cancel, :invalid_job}

  defp unexpected_failure(context, id, job_id, attempt) do
    Events.emit(context, :identification, :failed, %{
      file_id: id,
      job_id: job_id,
      attempt: attempt,
      reason: :unexpected_failure,
      failure_stage: :execution
    })

    {:error, :unexpected_failure}
  end
end

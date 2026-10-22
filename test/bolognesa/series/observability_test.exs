defmodule Bolognesa.Series.ObservabilityTest do
  use ExUnit.Case, async: false
  alias Bolognesa.Series.Application.UseCases.IdentifySeriesFile, as: Identify

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification, as: Correct
  alias Bolognesa.Series.Application.UseCases.ReconcileIdentificationJobs, as: Reconcile
  alias Bolognesa.Series.Application.UseCases.RetryIdentification, as: Retry
  alias Bolognesa.Series.Application.UseCases.SearchSeriesCandidates, as: Search
  alias Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker, as: Worker

  defmodule Repository do
    def find_file(_), do: {:ok, %{content_type: :series, revision: 3}}
    def correct(_, _, _), do: Process.get(:correction_result, {:ok, %{observed_revision: 3}})

    def correct_series(_, _, _),
      do: Process.get(:correction_result, {:ok, %{observed_revision: 3}})

    def retry(_), do: Process.get(:retry_result, {:ok, %{job_id: 34, observed_revision: 3}})
    def reconcile_jobs_result(_), do: Process.get(:recovery_result, {:ok, 0})

    def begin_identification(_, _, _),
      do:
        Process.get(
          :begin_result,
          {:ok, %{content_type: :series, relative_path: "Film.S01E01.mkv", revision: 3}}
        )

    def complete(_, _, _, _, _), do: Process.get(:write_result, :ok)
    def complete_series(_, _, _, _, _), do: Process.get(:write_result, :ok)
    def fail(_, _, _), do: Process.get(:write_result, :ok)
  end

  defmodule Provider do
    def search(_, _), do: Process.get(:search_result, {:ok, []})
    def details(_), do: {:error, :rate_limited}
  end

  setup do
    owner = self()
    id = {__MODULE__, make_ref()}

    names =
      for resource <- [:identification, :provider, :correction, :reconciliation],
          outcome <- [:started, :completed, :stale, :retryable, :failed, :requested, :recovered],
          do: [:bolognesa, :series, resource, outcome]

    :telemetry.attach_many(
      id,
      names,
      fn event, measurements, metadata, _ ->
        send(owner, {:observation, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    :ok
  end

  test "committed no-match is correlated and stale writes never announce completion" do
    assert :ok = Identify.call(21, "secret request", 2, Repository, Provider, 33)

    assert_receive {:observation, [:bolognesa, :series, :identification, :started], %{count: 1},
                    %{file_id: 21, job_id: 33, attempt: 2}}

    assert_receive {:observation, [:bolognesa, :series, :identification, :completed],
                    %{duration_ms: duration}, %{result: :no_match}}

    assert duration >= 0
    Process.put(:write_result, {:ok, :stale})
    assert :ok = Identify.call(21, "secret request", 2, Repository, Provider, 33)
    assert_receive {:observation, [:bolognesa, :series, :identification, :stale], _, _}
    refute_receive {:observation, [:bolognesa, :series, :identification, :completed], _, _}
  end

  test "stale admission stays quiet except the stale observation" do
    Process.put(:begin_result, {:ok, :stale})
    assert :ok = Identify.call(21, "secret request", 1, Repository, Provider, 33)
    assert_receive {:observation, [:bolognesa, :series, :identification, :stale], _, metadata}
    refute inspect(metadata) =~ "secret"
    refute_receive {:observation, [:bolognesa, :series, :identification, :started], _, _}
  end

  test "transient provider failures and committed exhaustion differ from failed persistence" do
    Process.put(:search_result, {:error, :rate_limited})

    assert {:error, :rate_limited} =
             Identify.call(21, "secret request", 1, Repository, Provider, 33)

    assert_receive {:observation, [:bolognesa, :series, :identification, :retryable], _,
                    %{reason: :rate_limited, failure_stage: :search}}

    assert :ok = Identify.call(21, "secret request", 3, Repository, Provider, 33)

    assert_receive {:observation, [:bolognesa, :series, :identification, :failed], _,
                    %{reason: :rate_limited}}

    Process.put(:write_result, {:error, :unavailable})

    assert {:error, :unavailable} =
             Identify.call(21, "secret request", 3, Repository, Provider, 33)

    assert_receive {:observation, [:bolognesa, :series, :identification, :retryable], _,
                    %{reason: :storage_unavailable}}

    refute_receive {:observation, [:bolognesa, :series, :identification, :failed], _, _}
  end

  test "explicit retry observes only the persisted replacement job" do
    actor = %AuthenticatedUser{id: 7, role: :admin}
    assert {:ok, _} = Retry.call(actor, 21, Repository)

    assert_receive {:observation, [:bolognesa, :series, :identification, :requested], _,
                    %{job_id: 34, file_id: 21, operation: :retry}}

    Process.put(:retry_result, {:error, :manual_locked})
    assert {:error, :manual_locked} = Retry.call(actor, 21, Repository)
    refute_receive {:observation, [:bolognesa, :series, :identification, :requested], _, _}
    Process.put(:retry_result, {:error, :unavailable})
    assert {:error, :unavailable} = Retry.call(actor, 21, Repository)

    assert_receive {:observation, [:bolognesa, :series, :identification, :retryable], _,
                    %{operation: :retry, reason: :storage_unavailable}}
  end

  test "manual correction commits, races and provider failure have distinct observations" do
    actor = %AuthenticatedUser{id: 7, role: :admin}
    assert {:ok, _} = Correct.call(actor, 21, :unidentified, Repository, Provider)

    assert_receive {:observation, [:bolognesa, :series, :correction, :completed], _,
                    %{file_id: 21, user_id: 7}}

    Process.put(:correction_result, {:error, :source_changed})

    assert {:error, :source_changed} =
             Correct.call(actor, 21, :unidentified, Repository, Provider)

    assert_receive {:observation, [:bolognesa, :series, :correction, :stale], _,
                    %{reason: :source_changed}}

    refute_receive {:observation, [:bolognesa, :series, :correction, :completed], _, _}

    assert {:error, :rate_limited} =
             Correct.call(actor, 21, {:tmdb, 42, 1, [1]}, Repository, Provider)

    assert_receive {:observation, [:bolognesa, :series, :correction, :failed], _,
                    %{reason: :rate_limited, failure_stage: :details}}

    refute_receive {:observation, [:bolognesa, :series, :provider, :failed], _, _}
  end

  test "manual search failures have one owner and never include the query" do
    actor = %AuthenticatedUser{id: 7, role: :admin}
    Process.put(:search_result, {:error, :provider_unavailable})
    assert {:error, :provider_unavailable} = Search.call(actor, "private media query", Provider)
    assert_receive {:observation, [:bolognesa, :series, :provider, :failed], _, metadata}
    assert metadata.reason == :provider_unavailable
    assert metadata.operation == :search
    refute inspect(metadata) =~ "private"
    refute_receive {:observation, [:bolognesa, :series, :provider, :failed], _, _}
  end

  test "idle recovery is quiet and partial recovery reports committed count" do
    assert :ok = Reconcile.call(DateTime.utc_now(), Repository)
    refute_receive {:observation, [:bolognesa, :series, :reconciliation, _], _, _}
    Process.put(:recovery_result, {:ok, 4})
    assert :ok = Reconcile.call(DateTime.utc_now(), Repository)

    assert_receive {:observation, [:bolognesa, :series, :reconciliation, :recovered],
                    %{recovered_count: 4}, _}

    Process.put(:recovery_result, {:error, :unavailable, 2})
    assert {:error, :unavailable} = Reconcile.call(DateTime.utc_now(), Repository)

    assert_receive {:observation, [:bolognesa, :series, :reconciliation, :failed],
                    %{recovered_count: 2}, %{reason: :storage_unavailable}}
  end

  test "uncaught worker exception is observed without exception or request content" do
    Process.put(:search_result, :invalid_provider_return)

    job = %Oban.Job{
      id: 33,
      args: %{"file_id" => 21, "token" => "private request token"},
      attempt: 1
    }

    assert {:error, :unexpected_failure} = Worker.perform(job, Repository, Provider)
    assert_receive {:observation, [:bolognesa, :series, :identification, :failed], _, metadata}

    assert metadata == %{
             file_id: 21,
             job_id: 33,
             attempt: 1,
             reason: :unexpected_failure,
             failure_stage: :execution
           }
  end
end

defmodule Bolognesa.Libraries.ObservabilityTest do
  use ExUnit.Case, async: false

  alias Bolognesa.Libraries.Application.UseCases.{DiscoverFiles, InspectMediaFile, ReconcileScans}
  alias Bolognesa.Libraries.Domain.ReadModels.ReconciliationResult
  alias Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  defmodule Repository do
    def begin_inspection(_, _, _),
      do: Process.get(:admission, {:ok, %{id: 11, library_id: 17, revision: 2}, %{id: 17}})

    def complete_inspection(_, _, _), do: Process.get(:completion, :ok)
    def fail_inspection(_, _, _, _), do: Process.get(:completion, :ok)
    def reconcile_jobs(_), do: Process.get(:recovery, %ReconciliationResult{})
    def begin_attempt(_, _), do: Process.get(:admission, {:ok, :terminal})
  end

  defmodule Probe do
    def inspect(_, _), do: Process.get(:probe, {:ok, :technical})
    def inspect_with_diagnostics(_, _), do: Process.get(:probe, {:ok, :technical})
  end

  defmodule Notifications do
    def notify(_), do: :ok
  end

  setup do
    owner = self()
    handler = {__MODULE__, make_ref()}

    events =
      for resource <- [:scan, :inspection, :reconciliation],
          outcome <- [:started, :completed, :stale, :failed, :retryable, :recovered],
          do: [:bolognesa, :libraries, resource, outcome]

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        fn event, measurements, metadata, _ ->
          send(owner, {:event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  test "inspection outcomes retain correlation and exclude the request token" do
    assert :ok = inspect_file()

    assert_receive {:event, [:bolognesa, :libraries, :inspection, :started], _,
                    %{file_id: 11, library_id: 17, job_id: 23, attempt: 1}}

    assert_receive {:event, [:bolognesa, :libraries, :inspection, :completed],
                    %{duration_ms: duration}, metadata}

    assert duration >= 0
    assert metadata.file_id == 11
    refute inspect(metadata) =~ "private-token"
  end

  test "stale completion does not announce success" do
    Process.put(:completion, {:ok, :stale})
    assert :ok = inspect_file()

    assert_receive {:event, [:bolognesa, :libraries, :inspection, :stale], _,
                    %{reason: :stale_attempt}}

    refute_receive {:event, [:bolognesa, :libraries, :inspection, :completed], _, _}
  end

  test "retryable attempt differs from persisted terminal failure" do
    Process.put(:probe, {:error, :timeout})
    assert {:error, :timeout} = inspect_file()

    assert_receive {:event, [:bolognesa, :libraries, :inspection, :retryable], _,
                    %{reason: :timeout, attempt: 1}}

    assert {:error, :timeout} = inspect_file(3)

    assert_receive {:event, [:bolognesa, :libraries, :inspection, :failed], _,
                    %{reason: :timeout, attempt: 3}}
  end

  test "failed terminal persistence emits retryable storage failure" do
    Process.put(:probe, {:error, :unreadable})
    Process.put(:completion, {:error, :unavailable})
    assert {:error, :storage_unavailable} = inspect_file()

    assert_receive {:event, [:bolognesa, :libraries, :inspection, :retryable], _,
                    %{reason: :storage_unavailable}}

    refute_receive {:event, [:bolognesa, :libraries, :inspection, :failed], _, _}
  end

  test "probe failure stage is retained on exactly one outcome" do
    Process.put(:probe, {:error, :unreadable, :ffprobe})
    assert :ok = inspect_file()
    assert_receive {:event, [:bolognesa, :libraries, :inspection, :started], _, _}

    assert_receive {:event, [:bolognesa, :libraries, :inspection, :failed], _,
                    %{reason: :unreadable, failure_stage: :ffprobe}}

    refute_receive {:event, _, _, _}
  end

  test "escaped private exceptions have one safe correlated worker observation" do
    job = %Oban.Job{
      id: 23,
      attempt: 2,
      args: %{"media_file_id" => 11, "token" => "private-token"}
    }

    Process.put(:admission, :raise_private)

    assert {:error, :unexpected_failure} =
             InspectionWorker.perform(
               job,
               Repository,
               Probe,
               Notifications
             )

    assert_receive {:event, [:bolognesa, :libraries, :inspection, :failed], _,
                    %{file_id: 11, job_id: 23, attempt: 2, reason: :unexpected_failure} = metadata}

    refute inspect(metadata) =~ "private"
    refute_receive {:event, _, _, _}
  end

  test "notification degradation is emitted once with safe library correlation" do
    owner = self()
    handler = {__MODULE__, :notification, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:bolognesa, :libraries, :notification, :degraded],
        fn event, measurements, metadata, _ ->
          send(owner, {:event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert :ok =
             LibraryStatusNotifications.notify(17,
               pubsub: :UnavailableObservabilityPubSub
             )

    assert_receive {:event, [:bolognesa, :libraries, :notification, :degraded], %{count: 1},
                    %{library_id: 17, reason: :notification_unavailable}}

    refute_receive {:event, _, _, _}
  end

  test "terminal scan replay is stale rather than another success" do
    assert :ok = DiscoverFiles.call(13, 2, Repository, nil, Notifications)

    assert_receive {:event, [:bolognesa, :libraries, :scan, :stale], _,
                    %{scan_id: 13, attempt: 2}}

    refute_receive {:event, [:bolognesa, :libraries, :scan, :completed], _, _}
  end

  test "partial recovery reports committed libraries independently from failure and idle polls" do
    Process.put(:recovery, %ReconciliationResult{
      changed_library_ids: [17, 17, 19],
      error: :unavailable
    })

    assert {:error, :unavailable} =
             ReconcileScans.call(DateTime.utc_now(), Repository, Notifications)

    assert_receive {:event, [:bolognesa, :libraries, :reconciliation, :recovered],
                    %{changed_library_count: 2}, %{operation: :scan}}

    assert_receive {:event, [:bolognesa, :libraries, :reconciliation, :retryable], _,
                    %{reason: :storage_unavailable}}

    Process.put(:recovery, %ReconciliationResult{})
    assert :ok = ReconcileScans.call(DateTime.utc_now(), Repository, Notifications)
    refute_receive {:event, _, _, _}
  end

  defp inspect_file(attempt \\ 1),
    do: InspectMediaFile.call(11, "private-token", attempt, Repository, Probe, Notifications, 23)
end

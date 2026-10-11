defmodule Bolognesa.Libraries.ScanDomainTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Libraries.Domain.Entities.{MediaFile, Scan}
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile

  @now ~U[2026-10-03 00:00:00Z]
  @later ~U[2026-10-03 00:01:00Z]
  @attrs %{relative_path: "Folder/MOVIE.MP4", size_bytes: 1, modified_at: @now}

  test "preserves subdirectories, case and whitespace without normalizing physical identity" do
    attrs = %{@attrs | relative_path: " Folder /MOVIE.MP4 "}
    assert {:ok, entry} = NewMediaFile.new(attrs)
    assert Map.from_struct(entry) == attrs
  end

  test "preserves a non UTF-8 filename as physical identity" do
    attrs = %{@attrs | relative_path: <<255, ".mp4">>}
    assert {:ok, entry} = NewMediaFile.new(attrs)
    assert entry.relative_path == <<255, ".mp4">>
    assert {:error, :invalid_entry} = NewMediaFile.new(%{attrs | relative_path: "../a.mp4"})
  end

  test "rejects absolute paths, traversal, empty components and NUL bytes" do
    for path <- [
          "/a.mp4",
          "../a.mp4",
          "a/../b.mp4",
          "",
          ".",
          "./a.mp4",
          "a//b.mp4",
          "a/",
          "a\0.mp4",
          nil
        ] do
      assert {:error, :invalid_entry} = NewMediaFile.new(%{@attrs | relative_path: path})
    end
  end

  test "requires nonnegative integer size and a UTC modification date" do
    assert {:ok, %{size_bytes: 0}} = NewMediaFile.new(%{@attrs | size_bytes: 0})

    for size <- [-1, 1.5, "1", nil] do
      assert {:error, :invalid_entry} = NewMediaFile.new(%{@attrs | size_bytes: size})
    end

    for date <- [
          nil,
          "2026-10-03",
          ~N[2026-10-03 00:00:00],
          %{@now | utc_offset: 3600},
          %{@now | month: 13}
        ] do
      assert {:error, :invalid_entry} = NewMediaFile.new(%{@attrs | modified_at: date})
    end
  end

  test "accepts only atom attribute keys and requires all entry fields" do
    assert {:error, :invalid_entry} =
             NewMediaFile.new(%{
               "relative_path" => "a.mp4",
               "size_bytes" => 1,
               "modified_at" => @now
             })

    assert {:error, :invalid_entry} = NewMediaFile.new(Map.put(@attrs, "size_bytes", 2))

    for field <- [:relative_path, :size_bytes, :modified_at] do
      assert {:error, :invalid_entry} = NewMediaFile.new(Map.delete(@attrs, field))
    end

    assert {:error, :invalid_entry} = NewMediaFile.new(nil)
  end

  test "starts a new media file at revision one" do
    assert {:ok, entry} = NewMediaFile.new(@attrs)
    assert MediaFile.revision_for(nil, entry) == 1
  end

  test "changes revision only when size or modification instant changes" do
    assert {:ok, entry} = NewMediaFile.new(@attrs)

    file =
      struct!(
        MediaFile,
        Map.merge(@attrs, %{
          id: 1,
          library_id: 2,
          revision: 4,
          availability: :missing,
          last_seen_generation: "generation"
        })
      )

    assert MediaFile.revision_for(file, entry) == 4
    assert MediaFile.revision_for(file, %{entry | size_bytes: 2}) == 5
    assert MediaFile.revision_for(file, %{entry | modified_at: @later}) == 5
    assert MediaFile.revision_for(file, %{entry | relative_path: "other.mp4"}) == 4
  end

  test "recognizes only queued, running and retrying scans as active" do
    for state <- [:queued, :running, :retrying], do: assert(Scan.active?(scan(state)))
    for state <- [:completed, :failed], do: refute(Scan.active?(scan(state)))
  end

  test "allows exactly the active scan transition graph" do
    allowed = %{
      queued: [:running, :retrying, :failed],
      running: [:running, :retrying, :completed, :failed],
      retrying: [:running, :failed]
    }

    for from <- [:queued, :running, :retrying],
        to <- [:queued, :running, :retrying, :completed, :failed] do
      reason = if to in [:retrying, :failed], do: :storage_unavailable, else: nil
      result = Scan.transition(scan(from), to, reason, @later)

      if to in Map.fetch!(allowed, from) do
        assert {:ok, %{state: ^to, updated_at: @later}} = result
      else
        assert {:error, :invalid_transition} = result
      end
    end
  end

  test "starts each attempt while preserving the first start time" do
    queued = scan(:queued)
    assert {:ok, running} = Scan.transition(queued, :running, nil, @now)
    assert running.started_at == @now
    assert running.attempt_started_at == @now

    assert {:ok, retried} =
             Scan.transition(%{running | failure_reason: :timeout}, :running, nil, @later)

    assert retried.started_at == @now
    assert retried.attempt_started_at == @later
    assert retried.failure_reason == nil
    assert retried.finished_at == nil
  end

  test "records sanitized failure reasons and terminal finish times" do
    for reason <- [
          :source_inaccessible,
          :source_outside_roots,
          :source_changed,
          :entry_unreadable,
          :unsafe_entry,
          :storage_unavailable,
          :timeout,
          :attempts_exhausted,
          :unexpected_failure
        ] do
      assert {:ok, retrying} = Scan.transition(scan(:running), :retrying, reason, @later)
      assert retrying.failure_reason == reason
      assert retrying.finished_at == nil
      assert {:ok, failed} = Scan.transition(retrying, :failed, reason, @later)
      assert failed.failure_reason == reason
      assert failed.finished_at == @later
    end

    assert {:ok, completed} =
             Scan.transition(
               %{scan(:running) | failure_reason: :timeout},
               :completed,
               nil,
               @later
             )

    assert completed.failure_reason == nil
    assert completed.finished_at == @later
  end

  test "rejects invalid states and mismatched failure reasons" do
    for state <- [:running, :completed] do
      assert {:error, :invalid_transition} =
               Scan.transition(scan(:running), state, :timeout, @later)
    end

    for state <- [:retrying, :failed], reason <- [nil, :unknown, "private failure"] do
      assert {:error, :invalid_transition} =
               Scan.transition(scan(:running), state, reason, @later)
    end

    assert {:error, :invalid_transition} = Scan.transition(scan(:running), :unknown, nil, @later)
  end

  test "terminal states never reopen and repeated terminal transitions never mutate data" do
    for state <- [:completed, :failed] do
      terminal = %{
        scan(state)
        | finished_at: @now,
          failure_reason: if(state == :failed, do: :timeout)
      }

      assert {:ok, ^terminal} = Scan.transition(terminal, state, :unexpected_failure, @later)

      for target <- [:queued, :running, :retrying, :completed, :failed] -- [state] do
        assert {:error, :invalid_transition} = Scan.transition(terminal, target, :timeout, @later)
      end
    end
  end

  test "status represents a library with no scan yet" do
    status = struct!(ScanStatus, library_id: 1, latest_scan: nil, last_completed_at: nil)
    assert status.library_id == 1
    assert status.latest_scan == nil
    assert status.last_completed_at == nil
  end

  defp scan(state) do
    struct!(Scan,
      id: 1,
      library_id: 2,
      job_id: 3,
      state: state,
      generation: nil,
      attempt: 0,
      files_discovered: 0,
      failure_reason: nil,
      requested_at: @now,
      started_at: nil,
      attempt_started_at: nil,
      finished_at: nil,
      updated_at: @now
    )
  end
end

defmodule BolognesaWeb.LiveSupport.PlaybackAttemptTest do
  use ExUnit.Case, async: true
  alias BolognesaWeb.LiveSupport.PlaybackAttempt

  @now 1_000_000
  @candidate %{
    id: "c0",
    transports: [:file],
    plan: %{configuration: %{mime: "video/mp4", video: "h264", audio: "aac"}}
  }

  defp checking(file_id \\ 3) do
    {attempt, [effect]} = PlaybackAttempt.select(PlaybackAttempt.new(), file_id)

    {attempt, _} =
      PlaybackAttempt.resolve(attempt, effect, {:ok, %{duration_ms: 60_000}, [@candidate]}, @now)

    attempt
  end

  describe "selecting a version" do
    test "stops the displayed session and asks for the file's candidates" do
      displayed = %{PlaybackAttempt.new() | session: %{id: "old"}, file_id: 2}

      assert {attempt, effects} = PlaybackAttempt.select(displayed, 3)

      assert effects == [{:stop_session, "old", :version_selected}, {:load_candidates, 3}]
      assert attempt.file_id == 3
      assert attempt.session == nil
      assert is_binary(attempt.id)
      refute attempt.recovery_used?
    end

    test "loaded candidates start a capability probe with a timeout" do
      {attempt, [effect]} = PlaybackAttempt.select(PlaybackAttempt.new(), 3)

      assert {checking, [{:schedule_capability_timeout, generation, 5_000}]} =
               PlaybackAttempt.resolve(
                 attempt,
                 effect,
                 {:ok, %{duration_ms: 60_000}, [@candidate]},
                 @now
               )

      assert checking.phase == :checking
      assert checking.duration_ms == 60_000

      assert checking.probe == %{
               generation: generation,
               candidates: [
                 %{
                   id: "c0",
                   transports: [:file],
                   configuration: %{mime: "video/mp4", video: "h264", audio: "aac"}
                 }
               ]
             }
    end

    test "a candidate error fails the attempt with its reason" do
      {attempt, [effect]} = PlaybackAttempt.select(PlaybackAttempt.new(), 3)

      assert {failed, []} = PlaybackAttempt.resolve(attempt, effect, {:error, :missing}, @now)
      assert failed.phase == :error
      assert failed.error == {:preparation, :missing}
    end

    test "the capability timeout fails only the probe it was scheduled for" do
      attempt = checking()

      assert PlaybackAttempt.capability_timed_out(attempt, "stale") == {attempt, []}

      assert {failed, []} =
               PlaybackAttempt.capability_timed_out(attempt, attempt.probe.generation)

      assert failed.error == {:preparation, :detection_unknown}
      assert failed.probe == nil
    end
  end

  @plan %{mode: :remux, transport: :hls}
  @session %{id: "s1", file_id: 3, duration_ms: 60_000, offset_ms: 0, plan: @plan}

  defp delivery(attempt, offset \\ 0, reason \\ :version_selected, autoplay \\ :keep),
    do: {:deliver, attempt.file_id, attempt.plan, offset, reason, autoplay}

  defp preparing do
    attempt = %{checking() | plan: @plan, probe: nil}

    {attempt, _} =
      PlaybackAttempt.resolve(attempt, delivery(attempt), {:ok, :transcode, @session}, @now)

    attempt
  end

  defp streaming do
    {attempt, _} =
      PlaybackAttempt.resolve(preparing(), {:fetch_status, "s1"}, :ready, @now)

    attempt
  end

  describe "delivery" do
    test "direct delivery is ready immediately and a conversion prepares with a poll" do
      attempt = %{checking() | plan: @plan, probe: nil}

      assert {%{phase: :ready, session: nil, file_id: 3}, []} =
               PlaybackAttempt.resolve(attempt, delivery(attempt), {:ok, :direct}, @now)

      assert {prepared, [{:schedule_poll, "s1", 250}]} =
               PlaybackAttempt.resolve(
                 attempt,
                 delivery(attempt),
                 {:ok, :transcode, @session},
                 @now
               )

      assert prepared.phase == :preparing
      assert prepared.session == @session
      assert prepared.stream_autoplay?
      assert prepared.deadline == @now + 60_000

      assert {%{error: {:preparation, :busy}}, []} =
               PlaybackAttempt.resolve(attempt, delivery(attempt), {:error, :busy}, @now)
    end

    test "a seek on the displayed stream redelivers at the offset and keeps the play state" do
      attempt = streaming()

      assert PlaybackAttempt.seek(attempt, %{"session_id" => "old", "position_ms" => "10"}) ==
               {attempt, []}

      assert PlaybackAttempt.seek(attempt, %{"session_id" => "s1", "position_ms" => "60001"}) ==
               {attempt, []}

      assert {^attempt, [effect]} =
               PlaybackAttempt.seek(attempt, %{
                 "session_id" => "s1",
                 "position_ms" => "30000",
                 "playing" => "false"
               })

      assert effect == delivery(attempt, 30_000, :seek, false)

      next = %{@session | id: "s2", offset_ms: 30_000}

      assert {%{session: ^next, stream_autoplay?: false}, _} =
               PlaybackAttempt.resolve(attempt, effect, {:ok, :transcode, next}, @now)
    end
  end

  describe "preparation polling" do
    test "a due poll checks only the session still preparing" do
      attempt = preparing()

      assert PlaybackAttempt.poll_due(attempt, "old") == {attempt, []}
      assert PlaybackAttempt.poll_due(attempt, "s1") == {attempt, [{:fetch_status, "s1"}]}

      failed = %{attempt | phase: :error, error: {:transcode, :interrupted}}
      assert PlaybackAttempt.poll_due(failed, "s1") == {failed, []}
    end

    test "a ready stream starts paused" do
      assert %{phase: :ready, stream_ready?: true, stream_paused?: true} = streaming()
    end

    test "waiting polls again until the sixty second deadline, then stops the session" do
      attempt = preparing()

      assert {%{phase: :preparing}, [{:schedule_poll, "s1", 500}]} =
               PlaybackAttempt.resolve(attempt, {:fetch_status, "s1"}, :waiting, @now + 45_000)

      assert {failed, [{:stop_session, "s1", :preparation_timeout}]} =
               PlaybackAttempt.resolve(attempt, {:fetch_status, "s1"}, :waiting, @now + 60_000)

      assert failed.error == {:transcode, :preparation}

      assert {%{error: {:transcode, :preparation}}, []} =
               PlaybackAttempt.resolve(attempt, {:fetch_status, "s1"}, {:error, :failed}, @now)
    end
  end

  defp failure(attempt, kind, position \\ "1000"),
    do: %{"attempt_id" => attempt.id, "error_kind" => kind, "position_ms" => position}

  defp with_report(attempt),
    do: %{attempt | report: %{"generation" => "g"}, candidates: [@candidate]}

  describe "client failures" do
    test "only failures of the current ready attempt within the media duration count" do
      attempt = with_report(streaming())
      params = Map.put(failure(attempt, "network"), "session_id", "s1")

      for stale <- [
            %{params | "attempt_id" => "previous"},
            %{params | "session_id" => "previous"},
            %{params | "position_ms" => "60001"}
          ] do
        assert PlaybackAttempt.client_failed(attempt, :session, stale) == {attempt, []}
      end

      direct = %{attempt | session: nil}
      file_params = Map.put(failure(direct, "network"), "file_id", "3")
      assert PlaybackAttempt.client_failed(attempt, :file, file_params) == {attempt, []}

      assert PlaybackAttempt.client_failed(direct, :file, %{file_params | "file_id" => "4"}) ==
               {direct, []}

      assert {%{error: {:transcode, :interrupted}}, []} =
               PlaybackAttempt.client_failed(direct, :file, file_params)
    end

    test "network, aborted and unknown failures stop the stream as interrupted" do
      attempt = with_report(streaming())

      for kind <- ["network", "aborted", "unknown"] do
        params = Map.put(failure(attempt, kind), "session_id", "s1")

        assert {%{error: {:transcode, :interrupted}}, [{:stop_session, "s1", :client_error}]} =
                 PlaybackAttempt.client_failed(attempt, :session, params)
      end

      params = Map.put(failure(attempt, "decode"), "session_id", "s1")
      assert PlaybackAttempt.client_failed(attempt, :session, params) == {attempt, []}
    end

    test "a media failure recovers once to a different compatible conversion" do
      attempt = with_report(streaming())
      params = Map.put(failure(attempt, "media", "2000"), "session_id", "s1")

      assert {recovering, [select]} = PlaybackAttempt.client_failed(attempt, :session, params)
      assert recovering.recovery_used?
      refute recovering.compatible_available?

      assert select ==
               {:select_plan, {:recovery, 2000}, 3, [@candidate],
                %{"generation" => "g", "preference" => "compatible"}}

      full = %{mode: :full_conversion, transport: :hls}

      assert {%{plan: ^full}, effects} =
               PlaybackAttempt.resolve(recovering, select, {:ok, full}, @now)

      assert effects == [
               {:stop_session, "s1", :client_error},
               {:deliver, 3, full, 2000, :session_replaced, :keep}
             ]

      assert {%{error: {:preparation, :unsupported}}, [{:stop_session, "s1", :client_error}]} =
               PlaybackAttempt.resolve(recovering, select, {:ok, @plan}, @now)

      assert {%{error: {:preparation, :busy}}, [{:stop_session, "s1", :client_error}]} =
               PlaybackAttempt.resolve(recovering, select, {:error, :busy}, @now)

      assert {%{error: {:transcode, :interrupted}}, [{:stop_session, "s1", :client_error}]} =
               PlaybackAttempt.client_failed(recovering, :session, params)
    end
  end

  describe "alternative playback" do
    test "compatible playback starts a new attempt with its own recovery when offered" do
      attempt = %{with_report(streaming()) | recovery_used?: true}

      assert PlaybackAttempt.play_compatible(attempt) == {attempt, []}

      offered = %{attempt | compatible_available?: true}

      assert {next, [{:select_plan, {:recovery, 0}, 3, _, _}]} =
               PlaybackAttempt.play_compatible(offered)

      assert next.id != offered.id
      assert next.recovery_used?
    end

    test "the original file plays directly without any later recovery" do
      attempt = with_report(streaming())

      assert PlaybackAttempt.play_original(%{attempt | file_id: nil}) ==
               {%{attempt | file_id: nil}, []}

      assert {^attempt, [effect]} = PlaybackAttempt.play_original(attempt)
      assert effect == {:prepare_original, 3}

      assert {original, [{:stop_session, "s1", :version_selected}]} =
               PlaybackAttempt.resolve(attempt, effect, {:ok, :direct}, @now)

      assert %{phase: :ready, session: nil, plan: nil, report: nil, recovery_used?: true} =
               original

      assert original.id != attempt.id

      assert {%{error: {:preparation, :missing}}, []} =
               PlaybackAttempt.resolve(attempt, effect, {:error, :missing}, @now)
    end

    test "an inspection refresh is requested once per file" do
      attempt = checking()

      assert {used, [effect]} = PlaybackAttempt.refresh(attempt)
      assert effect == {:refresh_inspection, 3}
      assert used.refresh_used?
      assert PlaybackAttempt.refresh(used) == {used, []}

      assert {%{refresh_requested?: true}, []} = PlaybackAttempt.resolve(used, effect, :ok, @now)

      assert {%{error: {:preparation, :missing}}, []} =
               PlaybackAttempt.resolve(used, effect, {:error, :missing}, @now)
    end
  end

  describe "the displayed stream" do
    test "pauses, resumes and ends only for its own session" do
      attempt = %{streaming() | stream_paused?: false}

      assert PlaybackAttempt.pause(attempt, "old") == {attempt, []}
      assert {%{stream_paused?: true}, []} = PlaybackAttempt.pause(attempt, "s1")

      assert PlaybackAttempt.ended(attempt, %{"session_id" => "old"}) == {attempt, []}
      assert PlaybackAttempt.ended(attempt, %{"file_id" => "3"}) == {attempt, []}

      assert {%{stream_paused?: true}, [{:stop_session, "s1", :ended}]} =
               PlaybackAttempt.ended(attempt, %{"session_id" => "s1"})
    end

    test "a resume restarts an expired session from the reported position" do
      attempt = streaming()
      params = %{"session_id" => "s1", "position_ms" => "5000"}

      assert PlaybackAttempt.resume(attempt, %{params | "session_id" => "old"}) == {attempt, []}
      assert PlaybackAttempt.resume(preparing(), params) |> elem(1) == []

      assert {^attempt, [effect]} = PlaybackAttempt.resume(attempt, params)
      assert effect == {:resume_session, "s1", 5000}
      assert {%{stream_paused?: false}, []} = PlaybackAttempt.resolve(attempt, effect, :ok, @now)

      assert PlaybackAttempt.resolve(attempt, effect, {:error, :not_found}, @now) ==
               {attempt, [{:deliver, 3, @plan, 5000, :session_replaced, :keep}]}

      invalid = {:resume_session, "s1", nil}

      assert PlaybackAttempt.resolve(attempt, invalid, {:error, :not_found}, @now) ==
               {attempt, []}
    end

    test "playing? recognizes only the playback in progress" do
      attempt = streaming()
      assert PlaybackAttempt.playing?(attempt, %{"session_id" => "s1"})
      refute PlaybackAttempt.playing?(attempt, %{"session_id" => "old"})
      refute PlaybackAttempt.playing?(attempt, %{"file_id" => "3"})

      direct = %{attempt | session: nil}
      assert PlaybackAttempt.playing?(direct, %{"file_id" => "3"})

      refute PlaybackAttempt.playing?(%{direct | error: {:transcode, :interrupted}}, %{
               "file_id" => "3"
             })

      refute PlaybackAttempt.playing?(direct, %{})
    end

    test "a restore succeeds only when the requested stream was replaced by a healthy one" do
      before = streaming()
      replaced = %{before | session: %{@session | id: "s2"}}

      assert PlaybackAttempt.restored?(before, replaced, "s1")
      refute PlaybackAttempt.restored?(before, replaced, "other")
      refute PlaybackAttempt.restored?(before, before, "s1")
      refute PlaybackAttempt.restored?(before, %{replaced | error: {:preparation, :busy}}, "s1")
      refute PlaybackAttempt.restored?(before, %{replaced | session: nil}, "s1")
      refute PlaybackAttempt.restored?(%{before | session: nil}, replaced, "s1")
    end

    test "a reset starts empty and stops the displayed session" do
      assert {%PlaybackAttempt{} = empty, [{:stop_session, "s1", :version_selected}]} =
               PlaybackAttempt.reset(streaming())

      assert empty == PlaybackAttempt.new()
    end
  end

  describe "a capability report" do
    test "asks for the requested plan only when it answers the current probe" do
      attempt = checking()
      report = %{"generation" => attempt.probe.generation, "preference" => "auto"}

      assert PlaybackAttempt.report(attempt, %{report | "generation" => "stale"}) == {attempt, []}
      assert PlaybackAttempt.report(%{attempt | phase: :ready}, report) |> elem(1) == []

      assert {^attempt, [{:select_plan, :requested, 3, [@candidate], ^report}]} =
               PlaybackAttempt.report(attempt, report)
    end

    test "an accepted plan is delivered from the start and checks for a compatible alternative" do
      attempt = checking()
      report = %{"generation" => attempt.probe.generation, "preference" => "auto"}
      {_, [effect]} = PlaybackAttempt.report(attempt, report)
      plan = %{mode: :direct, transport: :file}

      assert {accepted, effects} = PlaybackAttempt.resolve(attempt, effect, {:ok, plan}, @now)
      assert accepted.probe == nil
      assert accepted.plan == plan
      assert accepted.report == report

      compatible = Map.put(report, "preference", "compatible")

      assert effects == [
               {:select_plan, {:compatible_check, plan}, 3, [@candidate], compatible},
               {:deliver, 3, plan, 0, :version_selected, :keep}
             ]

      [check | _] = effects
      remux = %{mode: :remux, transport: :hls}

      assert {%{compatible_available?: true}, []} =
               PlaybackAttempt.resolve(accepted, check, {:ok, remux}, @now)

      assert {%{compatible_available?: false}, []} =
               PlaybackAttempt.resolve(accepted, check, {:ok, plan}, @now)

      assert {%{compatible_available?: false}, []} =
               PlaybackAttempt.resolve(accepted, check, {:error, :unsupported}, @now)
    end

    test "an invalid report is ignored and a negotiation error fails the attempt" do
      attempt = checking()
      {_, [effect]} = PlaybackAttempt.report(attempt, %{"generation" => attempt.probe.generation})

      assert PlaybackAttempt.resolve(attempt, effect, {:error, :invalid_report}, @now) ==
               {attempt, []}

      assert {%{error: {:preparation, :unsupported}}, []} =
               PlaybackAttempt.resolve(attempt, effect, {:error, :unsupported}, @now)
    end
  end
end

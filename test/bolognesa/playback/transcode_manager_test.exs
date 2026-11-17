defmodule Bolognesa.Playback.TranscodeManagerTest do
  alias Bolognesa.Playback, as: PlaybackContext
  use ExUnit.Case, async: false
  import Bolognesa.TranscodeFixtures
  alias Bolognesa.Playback.Infrastructure.TranscodeManager

  setup :transcode_source

  test "session lifecycle telemetry correlates offsets and precise stop causes", %{source: source} do
    attach_lifecycle()

    assert {:ok, session} =
             TranscodeManager.start(
               1,
               {:movie, 2},
               3,
               source,
               plan(source, :full_conversion),
               12_000
             )

    assert_receive {[:bolognesa, :playback, :session, :started], %{count: 1}, metadata}

    assert metadata == %{
             session_id: session.id,
             file_id: 3,
             strategy: :full_conversion,
             transport: :hls_js,
             offset_ms: 12_000
           }

    assert :ok = TranscodeManager.stop(session.id, :seek)
    assert_receive {[:bolognesa, :playback, :session, :closed], measurements, closed}
    assert measurements.count == 1
    assert measurements.duration_ms >= 0
    assert closed.reason == :seek
    assert closed.session_id == session.id
    refute Map.has_key?(closed, :path)
    refute Map.has_key?(closed, :actor_id)
  end

  test "reports preparation milestones and the final timeout snapshot", %{source: source} do
    attach_lifecycle()

    {:ok, session} =
      TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :audio_conversion), 0)

    assert PlaybackContext.video_transcode_status(session.id) == :waiting
    File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")

    File.write!(
      Path.join(session.directory, "index.m3u8"),
      "#EXTM3U\n#EXTINF:3.999,\nseg-000000.ts\n"
    )

    assert PlaybackContext.video_transcode_status(session.id) == :waiting

    assert_receive {[:bolognesa, :playback, :session, :preparation], first,
                    %{stage: :first_segment}}

    assert first.duration_ms >= 0
    assert first.published_ms == 3999
    assert first.segment_count == 1
    assert :ok = TranscodeManager.stop(session.id, :preparation_timeout)
    assert_receive {[:bolognesa, :playback, :session, :preparation], final, %{stage: :timeout}}
    assert final.published_ms == 3999
    assert final.segment_count == 1
    refute Map.has_key?(final, :first_progress_ms)
    refute Map.has_key?(final, :ffmpeg_output_ms)
  end

  test "FFmpeg progress is summarized at milestones without logging every report", %{
    source: source
  } do
    executable = Application.fetch_env!(:bolognesa, :ffmpeg_executable)

    File.write!(
      executable,
      "#!/bin/sh\nread line\nprintf 'frame=25\\nout_time_us=2500000\\nspeed=1.25x\\nprogress=continue\\n'\nread line\n"
    )

    attach_lifecycle()

    {:ok, session} =
      TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :audio_conversion), 0)

    assert_receive {[:bolognesa, :playback, :session, :started], started, _}
    assert started.prelaunch_ms >= 0
    assert started.spawn_ms >= 0
    %{port: port} = :sys.get_state(TranscodeManager)
    Port.command(port, "start\n")

    assert_receive {[:bolognesa, :playback, :session, :preparation], first,
                    %{stage: :first_progress}},
                   5_000

    assert first.ffmpeg_frame == 25
    assert first.ffmpeg_output_ms == 2500
    assert first.ffmpeg_speed_milli == 1250
    assert first.first_progress_ms >= 0

    assert :ok = TranscodeManager.stop(session.id, :preparation_timeout)
    assert_receive {[:bolognesa, :playback, :session, :preparation], final, %{stage: :timeout}}
    assert final.ffmpeg_output_ms == 2500
    assert final.progress_age_ms >= 0
    assert final.first_progress_ms == first.first_progress_ms
    refute_receive {[:bolognesa, :playback, :session, :preparation], _, _}
  end

  test "starts with four published seconds, including after a seek", %{source: source} do
    attach_lifecycle()

    for offset <- [0, 12_000] do
      {:ok, session} =
        TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), offset)

      path = Path.join(session.directory, "index.m3u8")
      File.write!(path, "#EXTM3U\n#EXTINF:4.0,\nseg-000000.ts\n")
      assert PlaybackContext.video_transcode_status(session.id) == :waiting
      File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")
      assert PlaybackContext.video_transcode_status(session.id) == :ready

      assert_receive {[:bolognesa, :playback, :session, :preparation], measurements,
                      %{stage: :ready}}

      assert measurements.segment_count == 1
      assert measurements.published_ms == 4000

      File.rm!(Path.join(session.directory, "seg-000000.ts"))
      assert PlaybackContext.video_transcode_status(session.id) == :waiting
    end
  end

  test "a long copied-video segment starts without waiting for the next GOP", %{source: source} do
    {:ok, session} =
      TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :audio_conversion), 0)

    File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")
    path = Path.join(session.directory, "index.m3u8")
    File.write!(path, "#EXTM3U\n#EXTINF:10.427,\nseg-000000.ts\n")
    assert PlaybackContext.video_transcode_status(session.id) == :ready
  end

  test "short segments accumulate four seconds and every referenced file must exist", %{
    source: source
  } do
    {:ok, session} =
      TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :audio_conversion), 0)

    path = Path.join(session.directory, "index.m3u8")
    File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")
    File.write!(path, "#EXTM3U\n#EXTINF:2.0,\nseg-000000.ts\n")
    assert PlaybackContext.video_transcode_status(session.id) == :waiting
    File.write!(path, "#EXTM3U\n#EXTINF:2.0,\nseg-000000.ts\n#EXTINF:2.0,\nseg-000001.ts\n")
    assert PlaybackContext.video_transcode_status(session.id) == :waiting
    File.write!(Path.join(session.directory, "seg-000001.ts"), "segment")
    assert PlaybackContext.video_transcode_status(session.id) == :ready
  end

  test "a short completed playlist can start without three segments", %{source: source} do
    {:ok, session} =
      TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 59_000)

    path = Path.join(session.directory, "index.m3u8")
    File.write!(path, "#EXTM3U\n#EXT-X-ENDLIST\n")
    assert PlaybackContext.video_transcode_status(session.id) == :waiting
    File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")
    File.write!(path, "#EXTM3U\n#EXTINF:1.0,\nseg-000000.ts\n#EXT-X-ENDLIST\n")
    assert PlaybackContext.video_transcode_status(session.id) == :ready
  end

  test "allows one running conversion and releases it on stop", %{source: source} do
    assert {:ok, session} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    assert {:error, :busy} =
             TranscodeManager.start(2, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    assert {:ok, ^session} = TranscodeManager.lookup(session.id)
    assert :ok = TranscodeManager.stop(session.id)
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)

    assert {:ok, _} =
             TranscodeManager.start(
               1,
               {:movie, 2},
               3,
               source,
               plan(source, :full_conversion),
               1_000
             )
  end

  test "a new playback replaces the same actor's session", %{source: source} do
    assert {:ok, previous} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    assert {:ok, next} =
             TranscodeManager.start(1, {:movie, 4}, 5, source, plan(source, :full_conversion), 0)

    assert next.id != previous.id
    assert {:error, :not_found} = TranscodeManager.lookup(previous.id)
    refute File.exists?(previous.directory)
    assert {:ok, ^next} = TranscodeManager.lookup(next.id)
    assert :ok = TranscodeManager.stop(previous.id)
    assert {:ok, ^next} = TranscodeManager.lookup(next.id)
  end

  test "unavailable replacement source keeps the current session", %{source: source} do
    {:ok, previous} =
      TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    fragment = Path.join(previous.directory, "seg-000000.ts")
    File.write!(fragment, "published fragment")

    missing = %{source | relative_path: "missing.avi"}

    assert {:error, :unreadable} =
             TranscodeManager.start(1, {:movie, 4}, 5, missing, plan(source, :full_conversion), 0)

    assert {:ok, ^previous} = TranscodeManager.lookup(previous.id)
    assert File.read!(fragment) == "published fragment"
  end

  test "missing FFmpeg keeps the current session", %{source: source} do
    {:ok, previous} =
      TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    Application.put_env(:bolognesa, :ffmpeg_executable, Path.join(source.path, "missing-ffmpeg"))

    assert {:error, :tool_unavailable} =
             TranscodeManager.start(1, {:movie, 4}, 5, source, plan(source, :full_conversion), 0)

    assert {:ok, ^previous} = TranscodeManager.lookup(previous.id)
    assert File.dir?(previous.directory)
  end

  test "closing the owning page releases the conversion", %{source: source} do
    attach_lifecycle()
    caller = self()

    owner =
      spawn(fn ->
        send(
          caller,
          {:started,
           TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)}
        )

        receive do
          :close -> :ok
        end
      end)

    assert_receive {:started, {:ok, session}}, 5_000
    %{port: port} = :sys.get_state(TranscodeManager)
    ref = :erlang.monitor(:port, port)
    send(owner, :close)
    assert_receive {:DOWN, ^ref, :port, ^port, _}, 5_000

    assert_receive {[:bolognesa, :playback, :session, :closed], _,
                    %{
                      reason: :owner_terminated,
                      termination_reason: :normal
                    }}

    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    refute File.exists?(session.directory)
  end

  test "production pauses ahead of the browser's requests and continues as it catches up", %{
    source: source
  } do
    assert {:ok, session} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    publish(session, 0..6)
    assert :ok = TranscodeManager.touch(session.id, 0)
    refute suspended?()

    # Eight segments ahead of the last request is the bound.
    publish(session, 0..8)
    send(TranscodeManager, :tick)
    assert suspended?()

    # Requests while paused keep it suspended until the lead drops to five segments.
    assert :ok = TranscodeManager.touch(session.id, 2)
    assert suspended?()
    assert :ok = TranscodeManager.touch(session.id, 3)
    refute suspended?()

    # A request without a segment (resume) only renews activity.
    assert :ok = TranscodeManager.touch(session.id)
    assert :ok = TranscodeManager.stop(session.id)
    assert {:error, :not_found} = TranscodeManager.touch(session.id, 4)
  end

  test "an older segment request never lowers the bound", %{source: source} do
    {:ok, session} =
      TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    publish(session, 0..9)
    assert :ok = TranscodeManager.touch(session.id, 4)
    assert :ok = TranscodeManager.touch(session.id, 0)
    refute suspended?()
  end

  defp publish(session, numbers) do
    entries =
      Enum.map_join(numbers, fn n ->
        "#EXTINF:4.0,\nseg-#{String.pad_leading("#{n}", 6, "0")}.ts\n"
      end)

    File.write!(Path.join(session.directory, "index.m3u8"), "#EXTM3U\n" <> entries)
  end

  defp suspended?, do: :sys.get_state(TranscodeManager).suspended?

  test "supervised shutdown stops a suspended FFmpeg", %{source: source} do
    :ok = Supervisor.terminate_child(Bolognesa.Supervisor, TranscodeManager)
    on_exit(fn -> Supervisor.restart_child(Bolognesa.Supervisor, TranscodeManager) end)
    start_supervised!(TranscodeManager)

    {:ok, session} =
      TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    {:os_pid, os_pid} = Port.info(:sys.get_state(TranscodeManager).port, :os_pid)
    publish(session, 0..8)
    send(TranscodeManager, :tick)
    assert suspended?()

    :ok = stop_supervised(TranscodeManager)

    refute File.exists?(session.directory)
    assert eventually(fn -> not os_process_alive?(os_pid) end)
  end

  defp os_process_alive?(os_pid) do
    {_, status} = System.cmd("kill", ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true)
    status == 0
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(20)
        eventually(check, attempts - 1)
    end
  end

  test "the periodic check closes a session over the temporary-storage limit", %{source: source} do
    assert {:ok, session} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    # A sparse file reports a large size without using disk space.
    {:ok, file} = :file.open(Path.join(session.directory, "seg-000000.ts"), [:write, :raw])
    {:ok, _} = :file.position(file, 513 * 1_024 * 1_024)
    :ok = :file.truncate(file)
    :ok = :file.close(file)

    send(TranscodeManager, :tick)
    _ = :sys.get_state(TranscodeManager)

    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    refute File.exists?(session.directory)
  end

  test "a cleanly finished FFmpeg keeps its published session", %{source: source} do
    done = Path.join(source.path, "done-ffmpeg")
    File.write!(done, "#!/bin/sh\nread line\nexit 0\n")
    File.chmod!(done, 0o700)
    good = Application.fetch_env!(:bolognesa, :ffmpeg_executable)
    Application.put_env(:bolognesa, :ffmpeg_executable, done)
    on_exit(fn -> Application.put_env(:bolognesa, :ffmpeg_executable, good) end)

    assert {:ok, session} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    %{port: port} = :sys.get_state(TranscodeManager)
    ref = :erlang.monitor(:port, port)
    Port.command(port, "\n")
    assert_receive {:DOWN, ^ref, :port, ^port, _}, 5_000
    _ = :sys.get_state(TranscodeManager)

    assert {:ok, %{status: :finished}} = TranscodeManager.lookup(session.id)
    assert File.dir?(session.directory)
    publish(session, 0..8)
    assert :ok = TranscodeManager.touch(session.id, 0)
    refute suspended?()
  end

  test "logout cleanup only stops the matching actor", %{source: source} do
    assert {:ok, session} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    assert :ok = TranscodeManager.stop_by_actor(2)
    assert {:ok, _} = TranscodeManager.lookup(session.id)
    assert :ok = TranscodeManager.stop_by_actor(1)
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
  end

  test "rejects a temporary directory inside a media library", %{source: source} do
    Application.put_env(:bolognesa, :transcode_root, Path.join(source.path, "hls"))

    assert {:error, :unsafe_root} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)
  end

  test "a failed FFmpeg releases the only conversion slot", %{source: source} do
    bad = Path.join(source.path, "bad-ffmpeg")
    File.write!(bad, "#!/bin/sh\nread line\nexit 2\n")
    File.chmod!(bad, 0o700)
    good = Application.fetch_env!(:bolognesa, :ffmpeg_executable)
    Application.put_env(:bolognesa, :ffmpeg_executable, bad)

    assert {:ok, session} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)

    %{port: port} = :sys.get_state(TranscodeManager)
    ref = :erlang.monitor(:port, port)
    Port.command(port, "\n")
    assert_receive {:DOWN, ^ref, :port, ^port, _}, 5_000
    _ = :sys.get_state(TranscodeManager)
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    Application.put_env(:bolognesa, :ffmpeg_executable, good)

    assert {:ok, _} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, plan(source, :full_conversion), 0)
  end

  test "negotiated sessions retain the selected actions across a seek", %{source: original} do
    {source, plan} = negotiated_source(original)
    attach_lifecycle()
    assert {:ok, first} = TranscodeManager.start(1, {:movie, 2}, 3, source, plan, 0)

    assert_receive {[:bolognesa, :playback, :session, :started], _,
                    %{strategy: :remux, transport: :hls_js}}

    assert first.plan == plan
    assert first.plan.mode == :remux
    assert {:error, :busy} = TranscodeManager.start(2, {:movie, 2}, 3, source, plan, 0)
    assert {:ok, next} = TranscodeManager.start(1, {:movie, 2}, 3, source, plan, 10_000, :seek)
    assert next.plan == plan
    assert next.offset_ms == 10_000
    refute next.id == first.id
    refute File.exists?(first.directory)
  end
end

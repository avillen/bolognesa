defmodule Bolognesa.Playback.TranscodeManagerTest do
  use ExUnit.Case, async: false
  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Infrastructure.TranscodeManager
  alias BolognesaWeb.LiveSupport.PlaybackEvents

  setup do
    base =
      Path.join(
        hd(Application.fetch_env!(:bolognesa, :library_roots)),
        "transcode-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(base)
    {:ok, root} = LocalSourcePath.canonical_directory(base)
    source_path = Path.join(root, "original.avi")
    File.write!(source_path, "controlled source")
    {:ok, stat} = File.stat(source_path, time: :posix)
    executable = Path.join(root, "fake-ffmpeg")
    File.write!(executable, "#!/bin/sh\nwhile :; do sleep 1; done\n")
    File.chmod!(executable, 0o700)
    previous_root = Application.get_env(:bolognesa, :transcode_root)
    previous_executable = Application.get_env(:bolognesa, :ffmpeg_executable)

    transcode_root =
      Path.join(System.tmp_dir!(), "hls-test-#{System.unique_integer([:positive])}")

    Application.put_env(:bolognesa, :transcode_root, transcode_root)
    Application.put_env(:bolognesa, :ffmpeg_executable, executable)

    on_exit(fn ->
      TranscodeManager.stop_all()
      restore(:transcode_root, previous_root)
      restore(:ffmpeg_executable, previous_executable)
      File.rm_rf!(root)
      File.rm_rf!(transcode_root)
    end)

    source = %Source{
      path: root,
      relative_path: "original.avi",
      size_bytes: stat.size,
      modified_at: DateTime.from_unix!(stat.mtime),
      revision: 1,
      duration_ms: 60_000
    }

    %{source: source}
  end

  test "session lifecycle telemetry correlates offsets and precise stop causes", %{source: source} do
    attach_lifecycle()

    assert {:ok, session} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 12_000)

    assert_receive {[:bolognesa, :playback, :session, :started], %{count: 1}, metadata}

    assert metadata == %{
             session_id: session.id,
             file_id: 3,
             strategy: :full_transcode,
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

  test "an ended event and LiveView termination retain distinct close causes", %{source: source} do
    attach_lifecycle()

    for {action, expected} <- [{:ended, :ended}, {:terminate, :liveview_terminated}] do
      {:ok, session} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          current_scope: %{actor: %{id: 1}},
          transcode_session: session,
          transcode_paused?: false
        }
      }

      case action do
        :ended ->
          PlaybackEvents.handle_event("playback_ended", %{"session_id" => session.id}, socket)

        :terminate ->
          PlaybackEvents.terminate({:shutdown, :closed}, socket)
      end

      assert_receive {[:bolognesa, :playback, :session, :closed], _, %{reason: ^expected}}
    end
  end

  defp attach_lifecycle do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:bolognesa, :playback, :session, :started],
          [:bolognesa, :playback, :session, :closed]
        ],
        &__MODULE__.handle_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  @spec handle_telemetry([atom()], map(), map(), pid()) :: any()
  def handle_telemetry(event, measurements, metadata, caller),
    do: send(caller, {event, measurements, metadata})

  test "waits for three published segments, including after a seek", %{source: source} do
    for offset <- [0, 12_000] do
      {:ok, session} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, offset)
      names = ["seg-000000.ts", "seg-000001.ts", "seg-000002.ts"]
      Enum.each(names, &File.write!(Path.join(session.directory, &1), "segment"))

      for count <- [1, 2, 3] do
        manifest =
          "#EXTM3U\n" <>
            Enum.map_join(Enum.take(names, count), "", &("#EXTINF:4.0,\n" <> &1 <> "\n"))

        File.write!(Path.join(session.directory, "index.m3u8"), manifest)
        expected = if count == 3, do: :ready, else: :waiting
        assert Bolognesa.Playback.video_transcode_status(session.id) == expected
      end

      File.rm!(Path.join(session.directory, List.last(names)))
      assert Bolognesa.Playback.video_transcode_status(session.id) == :waiting
    end
  end

  test "a long copied-video segment supplies the cushion without waiting for three GOPs", %{
    source: source
  } do
    {:ok, session} = TranscodeManager.start(1, {:movie, 2}, 3, source, :audio_only, 0)
    File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")
    path = Path.join(session.directory, "index.m3u8")
    File.write!(path, "#EXTM3U\n#EXTINF:16.0,\nseg-000000.ts\n")
    assert Bolognesa.Playback.video_transcode_status(session.id) == :ready
  end

  test "a short completed playlist can start without three segments", %{source: source} do
    {:ok, session} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 59_000)
    path = Path.join(session.directory, "index.m3u8")
    File.write!(path, "#EXTM3U\n#EXT-X-ENDLIST\n")
    assert Bolognesa.Playback.video_transcode_status(session.id) == :waiting
    File.write!(Path.join(session.directory, "seg-000000.ts"), "segment")
    File.write!(path, "#EXTM3U\n#EXTINF:1.0,\nseg-000000.ts\n#EXT-X-ENDLIST\n")
    assert Bolognesa.Playback.video_transcode_status(session.id) == :ready
  end

  test "rejects malformed or untyped video references", %{source: source} do
    for ref <- [2, {:series, 2}, {:movie, 0}] do
      assert {:error, :not_found} = TranscodeManager.start(1, ref, 3, source, :full_transcode, 0)
    end
  end

  test "rejects a seek outside known duration", %{source: source} do
    assert {:error, :invalid_offset} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, -1)

    assert {:error, :invalid_offset} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 60_001)
  end

  test "allows one running conversion and releases it on stop", %{source: source} do
    assert {:ok, session} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
    assert {:error, :busy} = TranscodeManager.start(2, {:movie, 2}, 3, source, :full_transcode, 0)
    assert {:ok, ^session} = TranscodeManager.lookup(session.id)
    assert :ok = TranscodeManager.stop(session.id)
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    assert {:ok, _} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 1_000)
  end

  test "a new playback replaces the same actor's session", %{source: source} do
    assert {:ok, previous} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
    assert {:ok, next} = TranscodeManager.start(1, {:movie, 4}, 5, source, :full_transcode, 0)
    assert next.id != previous.id
    assert {:error, :not_found} = TranscodeManager.lookup(previous.id)
    refute File.exists?(previous.directory)
    assert {:ok, ^next} = TranscodeManager.lookup(next.id)
    assert :ok = TranscodeManager.stop(previous.id)
    assert {:ok, ^next} = TranscodeManager.lookup(next.id)
  end

  test "invalid replacement keeps the current session and its fragments", %{source: source} do
    {:ok, previous} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
    fragment = Path.join(previous.directory, "seg-000000.ts")
    File.write!(fragment, "published fragment")

    assert {:error, :invalid_offset} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 60_001)

    assert {:ok, ^previous} = TranscodeManager.lookup(previous.id)
    assert File.read!(fragment) == "published fragment"
    assert :ok = TranscodeManager.suspend(previous.id)
    assert :ok = TranscodeManager.resume(previous.id)
  end

  test "unavailable replacement source keeps the current session", %{source: source} do
    {:ok, previous} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
    missing = %{source | relative_path: "missing.avi"}

    assert {:error, :unreadable} =
             TranscodeManager.start(1, {:movie, 4}, 5, missing, :full_transcode, 0)

    assert {:ok, ^previous} = TranscodeManager.lookup(previous.id)
    assert File.dir?(previous.directory)
  end

  test "missing FFmpeg keeps the current session", %{source: source} do
    {:ok, previous} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
    Application.put_env(:bolognesa, :ffmpeg_executable, Path.join(source.path, "missing-ffmpeg"))

    assert {:error, :tool_unavailable} =
             TranscodeManager.start(1, {:movie, 4}, 5, source, :full_transcode, 0)

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
          {:started, TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)}
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

  test "suspends production until playback resumes", %{source: source} do
    assert {:ok, session} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
    assert :ok = TranscodeManager.suspend(session.id)
    assert :ok = TranscodeManager.resume(session.id)
    assert :ok = TranscodeManager.stop(session.id)
    assert {:error, :not_found} = TranscodeManager.resume(session.id)
  end

  test "the ended event releases only the displayed session", %{source: source} do
    assert {:ok, session} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_scope: %{actor: %{id: 1}},
        transcode_session: session,
        transcode_paused?: false
      }
    }

    assert {:noreply, ^socket} =
             PlaybackEvents.handle_event(
               "playback_ended",
               %{"session_id" => "obsolete"},
               socket
             )

    assert {:ok, _} = TranscodeManager.lookup(session.id)

    assert {:noreply, next} =
             PlaybackEvents.handle_event(
               "playback_ended",
               %{"session_id" => session.id},
               socket
             )

    assert next.assigns.transcode_paused?
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
  end

  test "logout cleanup only stops the matching actor", %{source: source} do
    assert {:ok, session} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
    assert :ok = TranscodeManager.stop_by_actor(2)
    assert {:ok, _} = TranscodeManager.lookup(session.id)
    assert :ok = TranscodeManager.stop_by_actor(1)
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
  end

  test "rejects a temporary directory inside a media library", %{source: source} do
    Application.put_env(:bolognesa, :transcode_root, Path.join(source.path, "hls"))

    assert {:error, :unsafe_root} =
             TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
  end

  test "a failed FFmpeg releases the only conversion slot", %{source: source} do
    bad = Path.join(source.path, "bad-ffmpeg")
    File.write!(bad, "#!/bin/sh\nread line\nexit 2\n")
    File.chmod!(bad, 0o700)
    good = Application.fetch_env!(:bolognesa, :ffmpeg_executable)
    Application.put_env(:bolognesa, :ffmpeg_executable, bad)
    assert {:ok, session} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
    %{port: port} = :sys.get_state(TranscodeManager)
    ref = :erlang.monitor(:port, port)
    Port.command(port, "\n")
    assert_receive {:DOWN, ^ref, :port, ^port, _}, 5_000
    _ = :sys.get_state(TranscodeManager)
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    Application.put_env(:bolognesa, :ffmpeg_executable, good)
    assert {:ok, _} = TranscodeManager.start(1, {:movie, 2}, 3, source, :full_transcode, 0)
  end

  defp restore(key, nil), do: Application.delete_env(:bolognesa, key)
  defp restore(key, value), do: Application.put_env(:bolognesa, key, value)
end

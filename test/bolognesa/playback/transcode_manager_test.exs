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

  test "rejects a seek outside known duration", %{source: source} do
    assert {:error, :invalid_offset} = TranscodeManager.start(1, 2, 3, source, :video, -1)
    assert {:error, :invalid_offset} = TranscodeManager.start(1, 2, 3, source, :video, 60_001)
  end

  test "allows one running conversion and releases it on stop", %{source: source} do
    assert {:ok, session} = TranscodeManager.start(1, 2, 3, source, :video, 0)
    assert {:error, :busy} = TranscodeManager.start(2, 2, 3, source, :video, 0)
    assert {:ok, ^session} = TranscodeManager.lookup(session.id)
    assert :ok = TranscodeManager.stop(session.id)
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    assert {:ok, _} = TranscodeManager.start(1, 2, 3, source, :video, 1_000)
  end

  test "a new playback replaces the same actor's session", %{source: source} do
    assert {:ok, previous} = TranscodeManager.start(1, 2, 3, source, :video, 0)
    assert {:ok, next} = TranscodeManager.start(1, 4, 5, source, :video, 0)
    assert next.id != previous.id
    assert {:error, :not_found} = TranscodeManager.lookup(previous.id)
    refute File.exists?(previous.directory)
    assert {:ok, ^next} = TranscodeManager.lookup(next.id)
    assert :ok = TranscodeManager.stop(previous.id)
    assert {:ok, ^next} = TranscodeManager.lookup(next.id)
  end

  test "closing the owning page releases the conversion", %{source: source} do
    caller = self()

    owner =
      spawn(fn ->
        send(caller, {:started, TranscodeManager.start(1, 2, 3, source, :video, 0)})

        receive do
          :close -> :ok
        end
      end)

    assert_receive {:started, {:ok, session}}
    %{port: port} = :sys.get_state(TranscodeManager)
    ref = :erlang.monitor(:port, port)
    send(owner, :close)
    assert_receive {:DOWN, ^ref, :port, ^port, _}, 5_000
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    refute File.exists?(session.directory)
  end

  test "suspends production until playback resumes", %{source: source} do
    assert {:ok, session} = TranscodeManager.start(1, 2, 3, source, :video, 0)
    assert :ok = TranscodeManager.suspend(session.id)
    assert :ok = TranscodeManager.resume(session.id)
    assert :ok = TranscodeManager.stop(session.id)
    assert {:error, :not_found} = TranscodeManager.resume(session.id)
  end

  test "the ended event releases only the displayed session", %{source: source} do
    assert {:ok, session} = TranscodeManager.start(1, 2, 3, source, :video, 0)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_scope: %{actor: %{id: 1}},
        compatible_session: session,
        compatible_paused?: false
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

    assert next.assigns.compatible_paused?
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
  end

  test "logout cleanup only stops the matching actor", %{source: source} do
    assert {:ok, session} = TranscodeManager.start(1, 2, 3, source, :video, 0)
    assert :ok = TranscodeManager.stop_by_actor(2)
    assert {:ok, _} = TranscodeManager.lookup(session.id)
    assert :ok = TranscodeManager.stop_by_actor(1)
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
  end

  test "rejects a temporary directory inside a media library", %{source: source} do
    Application.put_env(:bolognesa, :transcode_root, Path.join(source.path, "hls"))
    assert {:error, :unsafe_root} = TranscodeManager.start(1, 2, 3, source, :video, 0)
  end

  test "a failed FFmpeg releases the only conversion slot", %{source: source} do
    bad = Path.join(source.path, "bad-ffmpeg")
    File.write!(bad, "#!/bin/sh\nread line\nexit 2\n")
    File.chmod!(bad, 0o700)
    good = Application.fetch_env!(:bolognesa, :ffmpeg_executable)
    Application.put_env(:bolognesa, :ffmpeg_executable, bad)
    assert {:ok, session} = TranscodeManager.start(1, 2, 3, source, :video, 0)
    %{port: port} = :sys.get_state(TranscodeManager)
    ref = :erlang.monitor(:port, port)
    Port.command(port, "\n")
    assert_receive {:DOWN, ^ref, :port, ^port, _}, 5_000
    _ = :sys.get_state(TranscodeManager)
    assert {:error, :not_found} = TranscodeManager.lookup(session.id)
    Application.put_env(:bolognesa, :ffmpeg_executable, good)
    assert {:ok, _} = TranscodeManager.start(1, 2, 3, source, :video, 0)
  end

  defp restore(key, nil), do: Application.delete_env(:bolognesa, key)
  defp restore(key, value), do: Application.put_env(:bolognesa, key, value)
end

defmodule Bolognesa.Playback.Infrastructure.TranscodeManager do
  @moduledoc "Own one FFmpeg process and its private sliding HLS directory."
  alias Bolognesa.Infrastructure.LocalSourcePath
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef
  alias Bolognesa.Playback.Infrastructure.FfmpegArgs
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile
  use GenServer

  require Logger

  @idle_ms 300_000
  @tick_ms 5_000
  @max_bytes 512 * 1_024 * 1_024

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @spec start(
          pos_integer(),
          ContentRef.t(),
          pos_integer(),
          Source.t(),
          :audio | :video,
          integer()
        ) ::
          {:ok, TranscodeSession.t()} | {:error, atom()}
  def start(actor_id, content_ref, file_id, source, profile, offset_ms) do
    if ContentRef.valid?(content_ref) do
      GenServer.call(
        __MODULE__,
        {:start, actor_id, content_ref, file_id, source, profile, offset_ms}
      )
    else
      {:error, :not_found}
    end
  end

  @spec lookup(String.t()) :: {:ok, TranscodeSession.t()} | {:error, :not_found}
  def lookup(id), do: GenServer.call(__MODULE__, {:lookup, id})

  @spec touch(String.t()) :: :ok | {:error, :not_found}
  def touch(id), do: GenServer.call(__MODULE__, {:touch, id})

  @spec stop(String.t()) :: :ok
  def stop(id), do: GenServer.call(__MODULE__, {:stop, id})

  @spec suspend(String.t()) :: :ok | {:error, :not_found}
  def suspend(id), do: GenServer.call(__MODULE__, {:signal, id, :suspend})

  @spec resume(String.t()) :: :ok | {:error, :not_found}
  def resume(id), do: GenServer.call(__MODULE__, {:signal, id, :resume})

  @spec stop_all() :: :ok
  def stop_all, do: GenServer.call(__MODULE__, :stop_all)

  @spec stop_by_actor(pos_integer()) :: :ok
  def stop_by_actor(actor_id), do: GenServer.call(__MODULE__, {:stop_by_actor, actor_id})

  @impl true
  def init(_) do
    case root() do
      {:ok, root} ->
        remove_abandoned(root)
        Process.send_after(self(), :tick, @tick_ms)

        {:ok,
         %{
           current: nil,
           port: nil,
           owner_ref: nil,
           last_activity: nil,
           root: root,
           suspended?: false
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(
        {:start, actor_id, content_ref, file_id, source, profile, offset_ms},
        {owner, _tag},
        state
      ) do
    state = replace_actor_session(state, actor_id)

    case start_session(state, actor_id, content_ref, file_id, source, profile, offset_ms) do
      {:ok, session, port, root} ->
        Logger.info("transcode_started session_id=#{session.id} profile=#{profile}")

        {:reply, {:ok, session},
         %{
           state
           | current: session,
             port: port,
             owner_ref: Process.monitor(owner),
             root: root,
             last_activity: now(),
             suspended?: false
         }}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:lookup, id}, _from, %{current: %{id: id} = session} = state),
    do: {:reply, {:ok, session}, state}

  def handle_call({:lookup, _id}, _from, state), do: {:reply, {:error, :not_found}, state}

  def handle_call({:touch, id}, _from, %{current: %{id: id}} = state),
    do: {:reply, :ok, %{state | last_activity: now()}}

  def handle_call({:touch, _id}, _from, state), do: {:reply, {:error, :not_found}, state}

  def handle_call({:signal, id, action}, _from, %{current: %{id: id}, port: port} = state)
      when not is_nil(port) do
    result = signal(port, if(action == :suspend, do: "STOP", else: "CONT"))

    case result do
      :ok ->
        {:reply, :ok, %{state | suspended?: action == :suspend, last_activity: now()}}

      _ ->
        {:reply, {:error, :not_found}, clear(state, :process_missing)}
    end
  end

  def handle_call({:signal, _id, _action}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call({:stop, id}, _from, %{current: %{id: id}} = state),
    do: {:reply, :ok, clear(state, :stopped)}

  def handle_call({:stop, _id}, _from, state), do: {:reply, :ok, state}
  def handle_call(:stop_all, _from, state), do: {:reply, :ok, clear(state, :stopped)}

  def handle_call({:stop_by_actor, actor_id}, _from, %{current: %{actor_id: actor_id}} = state),
    do: {:reply, :ok, clear(state, :logout)}

  def handle_call({:stop_by_actor, _actor_id}, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    session = state.current
    result = if status == 0, do: :finished, else: :failed
    Logger.info("transcode_ended session_id=#{session.id} reason=#{result}")

    if status == 0 do
      {:noreply, %{state | current: %{session | status: result}, port: nil, suspended?: false}}
    else
      {:noreply, clear(%{state | port: nil}, :failed)}
    end
  end

  def handle_info({port, {:data, _bytes}}, %{port: port} = state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _owner, _reason}, %{owner_ref: ref} = state),
    do: {:noreply, clear(state, :page_closed)}

  def handle_info({:DOWN, _ref, :process, _owner, _reason}, state), do: {:noreply, state}
  def handle_info({_port, _message}, state), do: {:noreply, state}

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    state = if stale?(state) or too_large?(state), do: clear(state, :limit), else: state
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state), do: clear(state, :shutdown)

  defp start_session(%{current: current}, _, _, _, _, _, _) when not is_nil(current),
    do: {:error, :busy}

  defp start_session(_state, actor_id, content_ref, file_id, source, profile, offset_ms) do
    with :ok <- valid_offset(source, offset_ms),
         {:ok, root} <- root(),
         {:ok, executable} <- executable(),
         {:ok, %{device: device}} <- LocalMediaFile.open(source),
         :ok <- :file.close(device),
         id = Ecto.UUID.generate(),
         directory = Path.join(root, "session-#{id}"),
         :ok <- File.mkdir(directory),
         :ok <- File.chmod(directory, 0o700) do
      session = %TranscodeSession{
        id: id,
        actor_id: actor_id,
        content_ref: content_ref,
        file_id: file_id,
        revision: source.revision,
        offset_ms: offset_ms,
        duration_ms: source.duration_ms,
        directory: directory,
        profile: profile
      }

      args =
        FfmpegArgs.for(
          profile,
          Path.join(source.path, source.relative_path),
          directory,
          offset_ms
        )

      try do
        port =
          Port.open({:spawn_executable, executable}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: args
          ])

        {:ok, session, port, root}
      rescue
        _ ->
          File.rm_rf(directory)
          {:error, :tool_unavailable}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_offset(%Source{duration_ms: duration}, offset)
       when is_integer(offset) and offset >= 0 and
              (is_nil(duration) or offset <= duration),
       do: :ok

  defp valid_offset(_, _), do: {:error, :invalid_offset}

  defp replace_actor_session(%{current: %{actor_id: actor_id}} = state, actor_id),
    do: clear(state, :replaced)

  defp replace_actor_session(state, _actor_id), do: state

  defp root do
    path = configured_transcode_path()
    expanded = Path.expand(path)
    libraries = configured_library_directories()

    if Path.type(path) != :absolute or inside_library?(expanded, libraries) do
      {:error, :unsafe_root}
    else
      ensure_transcode_directory(expanded)
    end
  end

  defp configured_transcode_path do
    Application.get_env(
      :bolognesa,
      :transcode_root,
      Path.join(System.tmp_dir!(), "bolognesa-transcode")
    )
  end

  defp configured_library_directories do
    Application.fetch_env!(:bolognesa, :library_roots)
    |> Enum.map(&resolve_library_directory/1)
  end

  defp resolve_library_directory(library) do
    case LocalSourcePath.canonical_directory(library) do
      {:ok, physical} -> physical
      _ -> Path.expand(library)
    end
  end

  defp ensure_transcode_directory(expanded) do
    case File.mkdir_p(expanded) do
      :ok -> verify_outside_libraries(expanded)
      {:error, _} -> {:error, :storage_unavailable}
    end
  end

  defp verify_outside_libraries(expanded) do
    case LocalSourcePath.canonical_directory(expanded) do
      {:error, :source_outside_roots} -> {:ok, expanded}
      _ -> {:error, :unsafe_root}
    end
  end

  defp inside_library?(path, libraries) do
    Enum.any?(libraries, fn library ->
      path == library or String.starts_with?(path, library <> "/")
    end)
  end

  defp remove_abandoned(root) do
    case File.ls(root) do
      {:ok, names} ->
        Enum.each(names, &remove_if_session(root, &1))

      _ ->
        :ok
    end
  end

  defp remove_if_session(root, name) do
    if Regex.match?(~r/\Asession-[0-9a-f-]{36}\z/, name) do
      File.rm_rf(Path.join(root, name))
    end
  end

  defp executable do
    executable =
      Application.get_env(:bolognesa, :ffmpeg_executable) ||
        System.find_executable("ffmpeg")

    if is_binary(executable), do: {:ok, executable}, else: {:error, :tool_unavailable}
  end

  defp stale?(%{current: nil}), do: false
  defp stale?(state), do: now() - state.last_activity > @idle_ms

  defp too_large?(%{current: nil}), do: false
  defp too_large?(state), do: directory_bytes(state.current.directory) > @max_bytes

  defp directory_bytes(directory) do
    directory
    |> File.ls!()
    |> Enum.reduce(0, fn name, total ->
      case File.stat(Path.join(directory, name)) do
        {:ok, %{type: :regular, size: size}} -> total + size
        _ -> total
      end
    end)
  rescue
    _ -> @max_bytes + 1
  end

  defp clear(%{current: nil} = state, _reason), do: state

  defp clear(state, reason) do
    if state.owner_ref, do: Process.demonitor(state.owner_ref, [:flush])

    if state.port do
      if state.suspended?, do: signal(state.port, "CONT")
      signal(state.port, "TERM")

      try do
        Port.close(state.port)
      rescue
        ArgumentError -> :ok
      end
    end

    File.rm_rf(state.current.directory)
    Logger.info("transcode_closed session_id=#{state.current.id} reason=#{reason}")
    %{state | current: nil, port: nil, owner_ref: nil, last_activity: nil, suspended?: false}
  end

  defp signal(port, name) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        {_, status} =
          System.cmd("sh", ["-c", "kill -#{name} \"$1\"", "sh", Integer.to_string(pid)],
            stderr_to_stdout: true
          )

        if status == 0, do: :ok, else: {:error, :process_missing}

      _ ->
        {:error, :process_missing}
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end

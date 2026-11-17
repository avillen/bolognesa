defmodule Bolognesa.Playback.Infrastructure.TranscodeManager do
  @moduledoc "Own one FFmpeg process and its private sliding HLS directory."
  alias Bolognesa.Infrastructure.Observability
  alias Bolognesa.Playback.Domain.Policies.Negotiation
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile
  alias Bolognesa.Playback.Infrastructure.TranscodeManager.FfmpegArgs
  alias Bolognesa.Playback.Infrastructure.TranscodeManager.FfmpegProcess
  alias Bolognesa.Playback.Infrastructure.TranscodeManager.HlsPlaylist
  alias Bolognesa.Playback.Infrastructure.TranscodeManager.Preparation
  alias Bolognesa.Playback.Infrastructure.TranscodeManager.Storage
  alias Bolognesa.Playback.Infrastructure.TranscodeManager.Telemetry
  alias Ecto.UUID
  use GenServer

  @idle_ms 300_000
  @tick_ms 5_000

  @empty %{
    current: nil,
    port: nil,
    owner_ref: nil,
    last_activity: nil,
    started_at: nil,
    suspended?: false,
    preparation: nil
  }

  @type stop_reason :: TranscodeSession.stop_reason()

  @type failure ::
          LocalMediaFile.failure()
          | :busy
          | :tool_unavailable
          | :unsafe_root
          | :storage_unavailable
          | :unsupported

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @spec start(
          pos_integer(),
          ContentRef.t(),
          pos_integer(),
          Source.t(),
          DeliveryPlan.t(),
          integer(),
          stop_reason() | :session_replaced
        ) :: {:ok, TranscodeSession.t()} | {:error, failure()}
  def start(
        actor_id,
        content_ref,
        file_id,
        source,
        strategy,
        offset_ms,
        replace_reason \\ :session_replaced
      ) do
    request = %{
      actor_id: actor_id,
      content_ref: content_ref,
      file_id: file_id,
      source: source,
      strategy: strategy,
      offset_ms: offset_ms,
      replace_reason: replace_reason
    }

    GenServer.call(__MODULE__, {:start, request})
  end

  @spec lookup(String.t()) :: {:ok, TranscodeSession.t()} | {:error, :not_found}
  def lookup(id), do: GenServer.call(__MODULE__, {:lookup, id})

  @spec status(String.t()) :: :ready | :waiting | :not_found
  def status(id), do: GenServer.call(__MODULE__, {:status, id})

  @spec touch(String.t()) :: :ok | {:error, :not_found}
  def touch(id), do: GenServer.call(__MODULE__, {:touch, id})

  @spec stop(String.t(), stop_reason()) :: :ok
  def stop(id, reason \\ :operator_stop)
      when reason in [
             :operator_stop,
             :version_selected,
             :seek,
             :ended,
             :client_error,
             :preparation_timeout,
             :source_invalidated,
             :liveview_terminated
           ],
      do: GenServer.call(__MODULE__, {:stop, id, reason})

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
    case Storage.root() do
      {:ok, root} ->
        # A suspended FFmpeg never gets SIGPIPE, so terminate/2 must run on shutdown.
        Process.flag(:trap_exit, true)
        Storage.remove_abandoned(root)
        Process.send_after(self(), :tick, @tick_ms)
        {:ok, @empty}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:start, request}, {owner, _tag}, state) do
    requested_at = now()

    with :ok <- available_slot(state, request.actor_id),
         {:ok, session, executable, args} <- prepare_session(request) do
      state = replace_actor_session(state, request.actor_id, request.replace_reason)
      launch_session(state, session, executable, args, owner, now() - requested_at)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:lookup, id}, _from, %{current: %{id: id} = session} = state),
    do: {:reply, {:ok, session}, state}

  def handle_call({:lookup, _id}, _from, state), do: {:reply, {:error, :not_found}, state}

  def handle_call({:status, id}, _from, %{current: %{id: id} = session} = state) do
    {status, count, published_ms} = HlsPlaylist.read(session.directory)
    preparation = Preparation.observe(state.preparation, status, count, published_ms)
    {:reply, status, %{state | preparation: preparation}}
  end

  def handle_call({:status, _id}, _from, state), do: {:reply, :not_found, state}

  def handle_call({:touch, id}, _from, %{current: %{id: id}} = state),
    do: {:reply, :ok, %{state | last_activity: now()}}

  def handle_call({:touch, _id}, _from, state), do: {:reply, {:error, :not_found}, state}

  def handle_call({:signal, id, action}, _from, %{current: %{id: id}, port: port} = state)
      when not is_nil(port) do
    case FfmpegProcess.signal(port, action) do
      :ok ->
        {:reply, :ok, %{state | suspended?: action == :suspend, last_activity: now()}}

      _ ->
        {:reply, {:error, :not_found}, clear(state, :process_missing)}
    end
  end

  def handle_call({:signal, _id, _action}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call({:stop, id, reason}, _from, %{current: %{id: id}} = state),
    do: {:reply, :ok, clear(state, reason)}

  def handle_call({:stop, _id, _reason}, _from, state), do: {:reply, :ok, state}
  def handle_call(:stop_all, _from, state), do: {:reply, :ok, clear(state, :operator_stop)}

  def handle_call({:stop_by_actor, actor_id}, _from, %{current: %{actor_id: actor_id}} = state),
    do: {:reply, :ok, clear(state, :logout)}

  def handle_call({:stop_by_actor, _actor_id}, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    session = state.current
    result = if status == 0, do: :finished, else: :failed
    Telemetry.emit(:exited, session, %{count: 1, exit_status: status}, %{reason: result})

    if status == 0 do
      {:noreply, %{state | current: %{session | status: result}, port: nil, suspended?: false}}
    else
      {:noreply, clear(%{state | port: nil}, :ffmpeg_failed)}
    end
  end

  def handle_info({port, {:data, line}}, %{port: port} = state),
    do: {:noreply, %{state | preparation: Preparation.consume(state.preparation, line)}}

  def handle_info({:DOWN, ref, :process, _owner, reason}, %{owner_ref: ref} = state) do
    {:noreply,
     clear(state, :owner_terminated, %{
       termination_reason: Observability.exit_reason(reason)
     })}
  end

  def handle_info({:DOWN, _ref, :process, _owner, _reason}, state), do: {:noreply, state}
  def handle_info({:EXIT, _from, _reason}, state), do: {:noreply, state}
  def handle_info({_port, _message}, state), do: {:noreply, state}

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, enforce_limits(state)}
  end

  @impl true
  def terminate(_reason, state), do: clear(state, :shutdown)

  defp enforce_limits(%{current: nil} = state), do: state

  defp enforce_limits(state) do
    cond do
      now() - state.last_activity > @idle_ms -> clear(state, :idle_timeout)
      Storage.over_limit?(state.current.directory) -> clear(state, :storage_limit)
      true -> state
    end
  end

  defp available_slot(%{current: nil}, _actor_id), do: :ok
  defp available_slot(%{current: %{actor_id: actor_id}}, actor_id), do: :ok
  defp available_slot(_state, _actor_id), do: {:error, :busy}

  defp prepare_session(request) do
    source = request.source

    with :ok <- validate_strategy(request.strategy, source),
         {:ok, root} <- Storage.root(),
         {:ok, executable} <- FfmpegProcess.executable(),
         :ok <- LocalMediaFile.validate(source),
         id = UUID.generate(),
         {:ok, directory} <- Storage.create_session_directory(root, id) do
      session = %TranscodeSession{
        id: id,
        actor_id: request.actor_id,
        content_ref: request.content_ref,
        file_id: request.file_id,
        revision: source.revision,
        offset_ms: request.offset_ms,
        duration_ms: source.duration_ms,
        directory: directory,
        plan: request.strategy
      }

      args =
        FfmpegArgs.for(
          session.plan,
          Path.join(source.path, source.relative_path),
          directory,
          session.offset_ms,
          threads: Application.get_env(:bolognesa, :transcode_threads, 2)
        )

      {:ok, session, executable, args}
    end
  end

  defp validate_strategy(%DeliveryPlan{mode: :direct}, _source), do: {:error, :unsupported}

  defp validate_strategy(%DeliveryPlan{} = plan, source),
    do: Negotiation.validate_plan(source, plan)

  defp validate_strategy(_, _), do: {:error, :unsupported}

  defp launch_session(state, session, executable, args, owner, prelaunch_ms) do
    spawn_started = now()

    case FfmpegProcess.open(executable, args) do
      {:ok, port} ->
        started_at = now()

        Telemetry.emit(
          :started,
          session,
          %{count: 1, prelaunch_ms: prelaunch_ms, spawn_ms: started_at - spawn_started},
          %{offset_ms: session.offset_ms}
        )

        {:reply, {:ok, session},
         %{
           state
           | current: session,
             port: port,
             owner_ref: Process.monitor(owner),
             last_activity: started_at,
             started_at: started_at,
             preparation: Preparation.new(session, started_at),
             suspended?: false
         }}

      {:error, reason} ->
        File.rm_rf(session.directory)
        {:reply, {:error, reason}, state}
    end
  end

  defp replace_actor_session(%{current: %{actor_id: actor_id}} = state, actor_id, reason),
    do: clear(state, reason)

  defp replace_actor_session(state, _actor_id, _reason), do: state

  defp clear(state, reason, metadata \\ %{})
  defp clear(%{current: nil} = state, _reason, _metadata), do: state

  defp clear(state, reason, metadata) do
    if reason == :preparation_timeout, do: Preparation.timed_out(state.preparation)
    if state.owner_ref, do: Process.demonitor(state.owner_ref, [:flush])

    FfmpegProcess.close(state.port, state.suspended?)
    File.rm_rf(state.current.directory)

    Telemetry.emit(
      :closed,
      state.current,
      %{count: 1, duration_ms: now() - state.started_at},
      Map.put(metadata, :reason, reason)
    )

    @empty
  end

  defp now, do: System.monotonic_time(:millisecond)
end

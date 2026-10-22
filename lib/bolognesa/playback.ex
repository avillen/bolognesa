defmodule Bolognesa.Playback do
  @moduledoc "Authorize audio and video sources for direct or transcode playback."

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Playback.Application.UseCases.StartTrackPlayback
  alias Bolognesa.Playback.Application.UseCases.StartVideoPlayback
  alias Bolognesa.Playback.Domain.Policies.TranscodeStrategy
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile
  alias Bolognesa.Playback.Infrastructure.Repositories.EctoPlaybackRepository
  alias Bolognesa.Playback.Infrastructure.TranscodeManager

  @type reason :: :forbidden | :not_found | :missing | :unavailable
  @type transcode_reason ::
          reason() | LocalMediaFile.failure() | TranscodeManager.failure() | :unsupported

  @spec start_video(AuthenticatedUser.t(), ContentRef.t(), integer()) ::
          {:ok, Source.t()} | {:error, :forbidden | :not_found | :missing | :unavailable}
  def start_video(actor, content_ref, file_id),
    do: StartVideoPlayback.call(actor, content_ref, file_id, EctoPlaybackRepository)

  @spec start_track(AuthenticatedUser.t() | nil, integer(), integer()) ::
          {:ok, Source.t()} | {:error, :forbidden | :not_found | :missing | :unavailable}
  def start_track(actor, track_id, file_id),
    do: StartTrackPlayback.call(actor, track_id, file_id, EctoPlaybackRepository)

  @spec prepare_video(AuthenticatedUser.t(), ContentRef.t(), integer()) ::
          {:ok, :direct}
          | {:ok, :transcode, TranscodeSession.t()}
          | {:error, transcode_reason()}
  def prepare_video(actor, content_ref, file_id) do
    with {:ok, strategy, source} <- video_delivery(actor, content_ref, file_id) do
      prepare_delivery(actor, content_ref, file_id, strategy, source)
    end
  end

  defp prepare_delivery(_actor, _content_ref, _file_id, :direct, source) do
    with :ok <- LocalMediaFile.validate(source), do: {:ok, :direct}
  end

  defp prepare_delivery(actor, content_ref, file_id, strategy, source) do
    with {:ok, session} <-
           TranscodeManager.start(
             actor.id,
             content_ref,
             file_id,
             source,
             strategy,
             0,
             :version_selected
           ) do
      {:ok, :transcode, session}
    end
  end

  @spec video_delivery(AuthenticatedUser.t(), ContentRef.t(), integer()) ::
          {:ok, :direct | :audio_only | :full_transcode, Source.t()} | {:error, reason()}
  def video_delivery(actor, content_ref, file_id) do
    with {:ok, source} <- start_video(actor, content_ref, file_id) do
      {:ok, TranscodeStrategy.choose(source), source}
    end
  end

  @spec start_video_transcode(
          AuthenticatedUser.t(),
          ContentRef.t(),
          integer(),
          integer(),
          :auto | :full_transcode,
          TranscodeManager.stop_reason() | :session_replaced
        ) ::
          {:ok, Bolognesa.Playback.Domain.ReadModels.TranscodeSession.t()}
          | {:error, transcode_reason()}
  def start_video_transcode(
        actor,
        content_ref,
        file_id,
        offset_ms,
        strategy_override \\ :auto,
        replace_reason \\ :session_replaced
      ) do
    with {:ok, strategy, source} <- video_delivery(actor, content_ref, file_id),
         :ok <- validate_strategy(strategy, strategy_override) do
      selected = selected_strategy(strategy, strategy_override)

      TranscodeManager.start(
        actor.id,
        content_ref,
        file_id,
        source,
        selected,
        offset_ms,
        replace_reason
      )
    end
  end

  defp selected_strategy(_strategy, :full_transcode), do: :full_transcode
  defp selected_strategy(strategy, _strategy_override), do: strategy

  @spec video_transcode_session(AuthenticatedUser.t(), ContentRef.t(), integer(), String.t()) ::
          {:ok, Bolognesa.Playback.Domain.ReadModels.TranscodeSession.t()}
          | {:error, transcode_reason()}
  def video_transcode_session(actor, content_ref, file_id, session_id) do
    with {:ok, session} <- TranscodeManager.lookup(session_id),
         true <-
           session.actor_id == actor.id and session.content_ref == content_ref and
             session.file_id == file_id do
      revalidate_session(actor, content_ref, file_id, session)
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revalidate_session(actor, content_ref, file_id, session) do
    case validate_transcode_source(actor, content_ref, file_id, session) do
      :ok ->
        {:ok, session}

      {:error, reason} ->
        TranscodeManager.stop(session.id, :source_invalidated)
        {:error, reason}
    end
  end

  defp validate_transcode_source(actor, content_ref, file_id, session) do
    with {:ok, source} <- start_video(actor, content_ref, file_id),
         true <- source.revision == session.revision,
         :ok <- LocalMediaFile.validate(source) do
      :ok
    else
      false -> {:error, :source_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_video_transcode(AuthenticatedUser.t(), String.t(), TranscodeManager.stop_reason()) ::
          :ok | {:error, :forbidden}
  def stop_video_transcode(actor, session_id, reason \\ :operator_stop) do
    case TranscodeManager.lookup(session_id) do
      {:ok, %{actor_id: actor_id}} when actor_id == actor.id ->
        TranscodeManager.stop(session_id, reason)

      {:error, :not_found} ->
        :ok

      _ ->
        {:error, :forbidden}
    end
  end

  @spec stop_actor_video_transcode(AuthenticatedUser.t()) :: :ok
  def stop_actor_video_transcode(actor), do: TranscodeManager.stop_by_actor(actor.id)

  @spec pause_video_transcode(AuthenticatedUser.t(), String.t()) :: :ok | {:error, :not_found}
  def pause_video_transcode(actor, session_id),
    do: signal_transcode(actor, session_id, :suspend)

  @spec resume_video_transcode(AuthenticatedUser.t(), String.t()) :: :ok | {:error, :not_found}
  def resume_video_transcode(actor, session_id),
    do: signal_transcode(actor, session_id, :resume)

  @spec video_transcode_status(String.t()) :: :ready | :waiting | :failed | :not_found
  def video_transcode_status(session_id) do
    case TranscodeManager.lookup(session_id) do
      {:ok, %{status: :failed}} -> :failed
      {:ok, session} -> playlist_status(session.directory)
      _ -> :not_found
    end
  end

  defp playlist_status(directory), do: if(playlist_ready?(directory), do: :ready, else: :waiting)

  defp playlist_ready?(directory) do
    case File.read(Path.join(directory, "index.m3u8")) do
      {:ok, manifest} -> manifest_ready?(directory, manifest)
      _ -> false
    end
  end

  defp manifest_ready?(directory, manifest) do
    segments = Regex.scan(~r/^seg-[0-9]{6,12}\.ts$/m, manifest) |> List.flatten()
    enough? = buffered_seconds(manifest) >= 12 or String.contains?(manifest, "#EXT-X-ENDLIST")

    enough? and segments != [] and
      Enum.all?(segments, &File.regular?(Path.join(directory, &1)))
  end

  defp buffered_seconds(manifest) do
    ~r/^#EXTINF:(\d+(?:\.\d+)?),/m
    |> Regex.scan(manifest, capture: :all_but_first)
    |> Enum.reduce(0.0, fn [duration], total ->
      {seconds, ""} = Float.parse(duration)
      total + seconds
    end)
  end

  defp validate_strategy(:direct, :auto), do: {:error, :unsupported}
  defp validate_strategy(_, _), do: :ok

  defp signal_transcode(actor, session_id, action) do
    with {:ok, session} <- TranscodeManager.lookup(session_id),
         true <- session.actor_id == actor.id do
      session |> signal_session(action) |> signal_result(session.status)
    else
      _ -> {:error, :not_found}
    end
  end

  defp signal_session(session, :suspend), do: TranscodeManager.suspend(session.id)
  defp signal_session(session, :resume), do: TranscodeManager.resume(session.id)
  defp signal_result({:error, :not_found}, :finished), do: :ok
  defp signal_result(result, _status), do: result
end

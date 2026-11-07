defmodule Bolognesa.Playback do
  @moduledoc "Authorize audio and video sources for direct or transcode playback."

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Playback.Application.UseCases.PrepareVideoDelivery
  alias Bolognesa.Playback.Application.UseCases.SelectVideoPlan
  alias Bolognesa.Playback.Application.UseCases.StartTrackPlayback
  alias Bolognesa.Playback.Application.UseCases.StartVideoPlayback
  alias Bolognesa.Playback.Domain.Policies.Negotiation
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan
  alias Bolognesa.Playback.Domain.ValueObjects.PlaybackCandidate
  alias Bolognesa.Playback.Infrastructure.LocalDeliveryExecutor
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile
  alias Bolognesa.Playback.Infrastructure.Repositories.EctoPlaybackRepository
  alias Bolognesa.Playback.Infrastructure.TranscodeManager

  @type reason :: :forbidden | :not_found | :missing | :unavailable
  @type negotiation_reason ::
          reason() | LocalMediaFile.failure() | Negotiation.error() | :invalid_report
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

  @spec prepare_video(
          AuthenticatedUser.t() | nil,
          ContentRef.t(),
          pos_integer(),
          DeliveryPlan.t(),
          non_neg_integer(),
          TranscodeSession.stop_reason() | :session_replaced
        ) ::
          {:ok, :direct} | {:ok, :transcode, TranscodeSession.t()} | {:error, transcode_reason()}
  def prepare_video(
        actor,
        content_ref,
        file_id,
        plan,
        offset_ms \\ 0,
        replace_reason \\ :version_selected
      ),
      do:
        PrepareVideoDelivery.call(
          actor,
          content_ref,
          file_id,
          plan,
          offset_ms,
          replace_reason,
          EctoPlaybackRepository,
          LocalDeliveryExecutor
        )

  @spec video_candidates(AuthenticatedUser.t(), ContentRef.t(), integer()) ::
          {:ok, Source.t(), [PlaybackCandidate.t()]}
          | {:error, negotiation_reason()}
  def video_candidates(actor, content_ref, file_id) do
    with {:ok, source} <- start_video(actor, content_ref, file_id),
         :ok <- LocalMediaFile.validate(source),
         {:ok, candidates} <- Negotiation.candidates(source) do
      {:ok, source, candidates}
    end
  end

  @spec select_video_plan(
          AuthenticatedUser.t(),
          ContentRef.t(),
          integer(),
          [PlaybackCandidate.t()],
          map(),
          String.t()
        ) ::
          {:ok, DeliveryPlan.t()} | {:error, SelectVideoPlan.error()}
  def select_video_plan(actor, content_ref, file_id, issued, raw, generation) do
    SelectVideoPlan.call(
      actor,
      content_ref,
      file_id,
      issued,
      raw,
      generation,
      EctoPlaybackRepository
    )
  end

  @spec prepare_original(AuthenticatedUser.t(), ContentRef.t(), integer()) ::
          {:ok, :direct} | {:error, transcode_reason()}
  def prepare_original(actor, content_ref, file_id) do
    with {:ok, source} <- start_video(actor, content_ref, file_id),
         :ok <- LocalMediaFile.validate(source),
         do: {:ok, :direct}
  end

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

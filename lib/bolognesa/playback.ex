defmodule Bolognesa.Playback do
  @moduledoc "Authorize a movie version for direct or compatible playback."

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Playback.Application.UseCases.StartPlayback
  alias Bolognesa.Playback.Application.UseCases.StartTrackPlayback
  alias Bolognesa.Playback.Domain.Policies.TranscodeProfile
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile
  alias Bolognesa.Playback.Infrastructure.Repositories.EctoPlaybackRepository
  alias Bolognesa.Playback.Infrastructure.TranscodeManager

  @type reason :: :forbidden | :not_found | :missing | :unavailable
  @type compatible_reason ::
          reason() | LocalMediaFile.failure() | TranscodeManager.failure() | :unsupported

  @spec start(AuthenticatedUser.t(), ContentRef.t(), integer()) ::
          {:ok, Source.t()} | {:error, :forbidden | :not_found | :missing | :unavailable}
  def start(actor, content_ref, file_id),
    do: StartPlayback.call(actor, content_ref, file_id, EctoPlaybackRepository)

  @spec start_track(AuthenticatedUser.t() | nil, integer(), integer()) ::
          {:ok, Source.t()} | {:error, :forbidden | :not_found | :missing | :unavailable}
  def start_track(actor, track_id, file_id),
    do: StartTrackPlayback.call(actor, track_id, file_id, EctoPlaybackRepository)

  @spec prepare(AuthenticatedUser.t(), ContentRef.t(), integer()) ::
          :ok
          | {:error, :forbidden | :not_found | :missing | :unavailable | LocalMediaFile.failure()}
  def prepare(actor, content_ref, file_id) do
    with {:ok, source} <- start(actor, content_ref, file_id),
         {:ok, %{device: device}} <- LocalMediaFile.open(source) do
      close_device(device)
    end
  end

  defp close_device(device) do
    case :file.close(device) do
      :ok -> :ok
      {:error, _} -> {:error, :unreadable}
    end
  end

  @spec delivery(AuthenticatedUser.t(), ContentRef.t(), integer()) ::
          {:ok, :direct | :audio | :video, Source.t()} | {:error, reason()}
  def delivery(actor, content_ref, file_id) do
    with {:ok, source} <- start(actor, content_ref, file_id) do
      {:ok, TranscodeProfile.choose(source), source}
    end
  end

  @spec start_compatible(
          AuthenticatedUser.t(),
          ContentRef.t(),
          integer(),
          integer(),
          :auto | :video
        ) ::
          {:ok, Bolognesa.Playback.Domain.ReadModels.TranscodeSession.t()}
          | {:error, compatible_reason()}
  def start_compatible(actor, content_ref, file_id, offset_ms, mode \\ :auto) do
    with {:ok, profile, source} <- delivery(actor, content_ref, file_id),
         :ok <- validate_profile(profile, mode) do
      selected = selected_profile(profile, mode)
      TranscodeManager.start(actor.id, content_ref, file_id, source, selected, offset_ms)
    end
  end

  defp selected_profile(_profile, :video), do: :video
  defp selected_profile(profile, _mode), do: profile

  @spec compatible_session(AuthenticatedUser.t(), ContentRef.t(), integer(), String.t()) ::
          {:ok, Bolognesa.Playback.Domain.ReadModels.TranscodeSession.t()}
          | {:error, compatible_reason()}
  def compatible_session(actor, content_ref, file_id, session_id) do
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
    case validate_compatible_source(actor, content_ref, file_id, session) do
      :ok ->
        {:ok, session}

      {:error, reason} ->
        TranscodeManager.stop(session.id)
        {:error, reason}
    end
  end

  defp validate_compatible_source(actor, content_ref, file_id, session) do
    with {:ok, source} <- start(actor, content_ref, file_id),
         true <- source.revision == session.revision,
         {:ok, %{device: device}} <- LocalMediaFile.open(source),
         :ok <- close_device(device) do
      :ok
    else
      false -> {:error, :source_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_compatible(AuthenticatedUser.t(), String.t()) :: :ok | {:error, :forbidden}
  def stop_compatible(actor, session_id) do
    case TranscodeManager.lookup(session_id) do
      {:ok, %{actor_id: actor_id}} when actor_id == actor.id -> TranscodeManager.stop(session_id)
      {:error, :not_found} -> :ok
      _ -> {:error, :forbidden}
    end
  end

  @spec stop_actor_compatible(AuthenticatedUser.t()) :: :ok
  def stop_actor_compatible(actor), do: TranscodeManager.stop_by_actor(actor.id)

  @spec pause_compatible(AuthenticatedUser.t(), String.t()) :: :ok | {:error, :not_found}
  def pause_compatible(actor, session_id), do: signal_compatible(actor, session_id, :suspend)

  @spec resume_compatible(AuthenticatedUser.t(), String.t()) :: :ok | {:error, :not_found}
  def resume_compatible(actor, session_id), do: signal_compatible(actor, session_id, :resume)

  @spec compatible_status(String.t()) :: :ready | :waiting | :failed | :not_found
  def compatible_status(session_id) do
    case TranscodeManager.lookup(session_id) do
      {:ok, %{status: :failed}} -> :failed
      {:ok, session} -> playlist_status(session.directory)
      _ -> :not_found
    end
  end

  defp playlist_status(directory), do: if(playlist_ready?(directory), do: :ready, else: :waiting)

  defp playlist_ready?(directory) do
    with {:ok, manifest} <- File.read(Path.join(directory, "index.m3u8")),
         [segment | _] <- Regex.run(~r/seg-[0-9]{6,12}\.ts/, manifest),
         true <- File.regular?(Path.join(directory, segment)) do
      true
    else
      _ -> false
    end
  end

  defp validate_profile(:direct, :auto), do: {:error, :unsupported}
  defp validate_profile(_, _), do: :ok

  defp signal_compatible(actor, session_id, action) do
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

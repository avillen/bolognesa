defmodule Bolognesa.Playback do
  @moduledoc "Authorize a movie version for direct or compatible playback."

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Playback.Application.UseCases.StartPlayback
  alias Bolognesa.Playback.Domain.Source
  alias Bolognesa.Playback.Domain.TranscodeProfile
  alias Bolognesa.Playback.Infrastructure.LocalMediaFile
  alias Bolognesa.Playback.Infrastructure.Repositories.EctoPlaybackRepository
  alias Bolognesa.Playback.Infrastructure.TranscodeManager

  @spec start(Actor.t(), integer(), integer()) ::
          {:ok, Source.t()} | {:error, :forbidden | :not_found | :missing | :unavailable}
  def start(actor, catalog_entry_id, file_id),
    do: StartPlayback.call(actor, catalog_entry_id, file_id, EctoPlaybackRepository)

  @spec prepare(Actor.t(), integer(), integer()) ::
          :ok
          | {:error, :forbidden | :not_found | :missing | :unavailable | LocalMediaFile.failure()}
  def prepare(actor, catalog_entry_id, file_id) do
    with {:ok, source} <- start(actor, catalog_entry_id, file_id),
         {:ok, %{device: device}} <- LocalMediaFile.open(source) do
      case :file.close(device) do
        :ok -> :ok
        {:error, _} -> {:error, :unreadable}
      end
    end
  end

  @spec delivery(Actor.t(), integer(), integer()) ::
          {:ok, :direct | :audio | :video, Source.t()} | {:error, atom()}
  def delivery(actor, catalog_entry_id, file_id) do
    with {:ok, source} <- start(actor, catalog_entry_id, file_id) do
      {:ok, TranscodeProfile.choose(source), source}
    end
  end

  @spec start_compatible(Actor.t(), integer(), integer(), integer(), :auto | :video) ::
          {:ok, Bolognesa.Playback.Domain.TranscodeSession.t()} | {:error, atom()}
  def start_compatible(actor, catalog_entry_id, file_id, offset_ms, mode \\ :auto) do
    with {:ok, profile, source} <- delivery(actor, catalog_entry_id, file_id),
         :ok <- validate_profile(profile, mode) do
      selected = if mode == :video, do: :video, else: profile
      TranscodeManager.start(actor.id, catalog_entry_id, file_id, source, selected, offset_ms)
    end
  end

  @spec compatible_session(Actor.t(), integer(), integer(), String.t()) ::
          {:ok, Bolognesa.Playback.Domain.TranscodeSession.t()} | {:error, atom()}
  def compatible_session(actor, catalog_entry_id, file_id, session_id) do
    with {:ok, session} <- TranscodeManager.lookup(session_id),
         true <-
           session.actor_id == actor.id and session.catalog_entry_id == catalog_entry_id and
             session.file_id == file_id do
      case validate_compatible_source(actor, catalog_entry_id, file_id, session) do
        :ok ->
          {:ok, session}

        {:error, reason} ->
          TranscodeManager.stop(session_id)
          {:error, reason}
      end
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_compatible_source(actor, catalog_entry_id, file_id, session) do
    with {:ok, source} <- start(actor, catalog_entry_id, file_id),
         true <- source.revision == session.revision,
         {:ok, %{device: device}} <- LocalMediaFile.open(source),
         :ok <- :file.close(device) do
      :ok
    else
      false -> {:error, :source_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_compatible(Actor.t(), String.t()) :: :ok | {:error, :forbidden}
  def stop_compatible(actor, session_id) do
    case TranscodeManager.lookup(session_id) do
      {:ok, %{actor_id: actor_id}} when actor_id == actor.id -> TranscodeManager.stop(session_id)
      {:error, :not_found} -> :ok
      _ -> {:error, :forbidden}
    end
  end

  @spec stop_actor_compatible(Actor.t()) :: :ok
  def stop_actor_compatible(actor), do: TranscodeManager.stop_by_actor(actor.id)

  @spec pause_compatible(Actor.t(), String.t()) :: :ok | {:error, :not_found}
  def pause_compatible(actor, session_id), do: signal_compatible(actor, session_id, :suspend)

  @spec resume_compatible(Actor.t(), String.t()) :: :ok | {:error, :not_found}
  def resume_compatible(actor, session_id), do: signal_compatible(actor, session_id, :resume)

  @spec compatible_status(String.t()) :: :ready | :waiting | :failed | :not_found
  def compatible_status(session_id) do
    case TranscodeManager.lookup(session_id) do
      {:ok, %{status: :failed}} -> :failed
      {:ok, session} -> if playlist_ready?(session.directory), do: :ready, else: :waiting
      _ -> :not_found
    end
  end

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
      result =
        if action == :suspend,
          do: TranscodeManager.suspend(session_id),
          else: TranscodeManager.resume(session_id)

      if result == {:error, :not_found} and session.status == :finished,
        do: :ok,
        else: result
    else
      _ -> {:error, :not_found}
    end
  end
end

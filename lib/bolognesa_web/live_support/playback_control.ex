defmodule BolognesaWeb.LiveSupport.PlaybackControl do
  @moduledoc "Coordinates authorized playback preparation and temporary sessions for the UI."
  import Phoenix.Component, only: [assign: 3]
  alias Bolognesa.Playback
  alias BolognesaWeb.LiveSupport.PlaybackState

  @spec select_version(Phoenix.LiveView.Socket.t(), pos_integer()) :: Phoenix.LiveView.Socket.t()
  def select_version(socket, file_id) do
    with %{versions: versions} <- socket.assigns.detail,
         true <- file_id > 0,
         %{availability: :available} <- Enum.find(versions, &(&1.id == file_id)) do
      prepare(socket, file_id)
    else
      _ -> socket
    end
  end

  defp prepare(socket, file_id) do
    stop_transcode(socket, :version_selected)
    socket = socket |> PlaybackState.direct(file_id) |> assign(:delivery_plan, nil)

    socket =
      socket
      |> assign(:playback_attempt_id, Ecto.UUID.generate())
      |> assign(:playback_duration_ms, nil)
      |> assign(:capability_report, nil)
      |> assign(:recovery_used?, false)
      |> assign(:inspection_refresh_used?, false)
      |> assign(:inspection_refresh_requested?, false)

    actor = socket.assigns.current_scope.actor

    case Playback.video_candidates(actor, socket.assigns.content_ref, file_id) do
      {:ok, source, candidates} ->
        generation = Ecto.UUID.generate()
        Process.send_after(self(), {:capability_timeout, generation}, 5_000)
        probe = %{generation: generation, candidates: Enum.map(candidates, &probe_candidate/1)}

        socket
        |> assign(:playback_duration_ms, source.duration_ms)
        |> assign(:playback_phase, :checking)
        |> assign(:playback_candidates, candidates)
        |> assign(:playback_probe, probe)
        |> assign(:inspection_refresh_used?, false)

      {:error, reason} ->
        PlaybackState.preparation_failed(socket, reason)
    end
  end

  @spec accept_report(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def accept_report(socket, raw) do
    probe = socket.assigns.playback_probe

    if !socket.assigns[:loading?] and socket.assigns.playback_phase == :checking and is_map(probe) and
         raw["generation"] == probe.generation do
      actor = socket.assigns.current_scope.actor

      case Playback.select_video_plan(
             actor,
             socket.assigns.content_ref,
             socket.assigns.selected_file_id,
             socket.assigns.playback_candidates,
             raw,
             probe.generation
           ) do
        {:ok, plan} ->
          socket
          |> assign(:playback_probe, nil)
          |> assign(:delivery_plan, plan)
          |> assign(:capability_report, raw)
          |> deliver(0, :version_selected)

        {:error, :invalid_report} ->
          socket

        {:error, reason} ->
          PlaybackState.preparation_failed(socket, reason)
      end
    else
      socket
    end
  end

  @spec deliver(
          Phoenix.LiveView.Socket.t(),
          non_neg_integer(),
          Bolognesa.Playback.Domain.ReadModels.TranscodeSession.stop_reason() | :session_replaced
        ) ::
          Phoenix.LiveView.Socket.t()
  def deliver(socket, offset_ms, reason) do
    case Playback.prepare_video(
           socket.assigns.current_scope.actor,
           socket.assigns.content_ref,
           socket.assigns.selected_file_id,
           socket.assigns.delivery_plan,
           offset_ms,
           reason
         ) do
      {:ok, :direct} -> PlaybackState.direct(socket, socket.assigns.selected_file_id)
      {:ok, :transcode, session} -> preparing(socket, session)
      {:error, reason} -> PlaybackState.preparation_failed(socket, reason)
    end
  end

  @spec recover(Phoenix.LiveView.Socket.t(), non_neg_integer()) :: Phoenix.LiveView.Socket.t()
  def recover(socket, offset) do
    raw = socket.assigns[:capability_report]

    if is_map(raw) and !socket.assigns.recovery_used? do
      socket = assign(socket, :recovery_used?, true)

      case Playback.select_video_plan(
             socket.assigns.current_scope.actor,
             socket.assigns.content_ref,
             socket.assigns.selected_file_id,
             socket.assigns.playback_candidates,
             Map.put(raw, "preference", "compatible"),
             raw["generation"]
           ) do
        {:ok, plan}
        when plan.mode != :direct and plan != socket.assigns.delivery_plan ->
          stop_transcode(socket, :client_error)
          socket |> assign(:delivery_plan, plan) |> deliver(offset, :session_replaced)

        {:error, reason} ->
          stop_transcode(socket, :client_error)
          PlaybackState.preparation_failed(socket, reason)

        _ ->
          stop_transcode(socket, :client_error)
          PlaybackState.preparation_failed(socket, :unsupported)
      end
    else
      stop_transcode(socket, :client_error)
      PlaybackState.transcode_failed(socket, :interrupted)
    end
  end

  defp probe_candidate(candidate) do
    config = candidate.plan.configuration

    %{
      id: candidate.id,
      transports: candidate.transports,
      configuration: %{mime: config.mime, video: config.video, audio: config.audio}
    }
  end

  @spec stop_transcode(
          Phoenix.LiveView.Socket.t(),
          Bolognesa.Playback.Infrastructure.TranscodeManager.stop_reason()
        ) :: :ok | {:error, :forbidden}
  def stop_transcode(socket, reason) do
    case socket.assigns.transcode_session do
      nil ->
        :ok

      session ->
        Playback.stop_video_transcode(socket.assigns.current_scope.actor, session.id, reason)
    end
  end

  defp preparing(socket, session) do
    Process.send_after(self(), {:transcode_poll, session.id}, 250)
    PlaybackState.preparing(socket, session)
  end
end

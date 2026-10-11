defmodule BolognesaWeb.Player do
  @moduledoc "Shared authorized playback controls for movie and episode pages."
  use BolognesaWeb, :html
  attr :prefix, :string, required: true
  attr :kind, :atom, required: true
  attr :entry_id, :integer, required: true
  attr :selected_file_id, :integer, default: nil
  attr :compatible_session, :any, default: nil
  attr :compatible_ready?, :boolean, required: true
  attr :compatible_paused?, :boolean, required: true
  attr :compatible_autoplay?, :boolean, required: true
  attr :playback_error, :string, default: nil
  attr :playback_error_reason, :string, default: nil
  @spec player(map()) :: Phoenix.LiveView.Rendered.t()
  def player(assigns) do
    ~H"""
    <section
      :if={@selected_file_id}
      id={"#{@prefix}-player"}
      class="mt-10 space-y-3"
      aria-label={gettext("Reproductor")}
    >
      <h2 class="text-xl font-semibold text-ink">
        {gettext("Reproduciendo versión %{id}", id: @selected_file_id)}
      </h2>
      <p
        :if={@compatible_session && !@compatible_ready? && !@playback_error}
        id={"#{@prefix}-playback-preparing"}
        role="status"
        data-session-id={@compatible_session.id}
        class="text-muted"
      >
        {gettext("Preparando reproducción…")}
      </p>
      <video
        :if={!@compatible_session}
        id={"#{@prefix}-video-#{@selected_file_id}"}
        phx-hook="VideoError"
        data-file-id={@selected_file_id}
        controls
        playsinline
        preload="metadata"
        src={media_url(@kind, @entry_id, @selected_file_id)}
        class="aspect-video w-full rounded-xl bg-black"
      >
        {gettext("Tu navegador no admite la reproducción de vídeo.")}
      </video>
      <div :if={@compatible_session && @compatible_ready?} class="space-y-3">
        <video
          id={"#{@prefix}-video-#{@compatible_session.id}"}
          phx-hook="CompatibleVideo"
          data-session-id={@compatible_session.id}
          data-paused-server={to_string(@compatible_paused?)}
          data-autoplay={to_string(@compatible_autoplay?)}
          data-offset-ms={@compatible_session.offset_ms}
          data-duration-ms={@compatible_session.duration_ms}
          data-src={hls_url(@kind, @entry_id, @selected_file_id, @compatible_session.id)}
          controls
          playsinline
          preload="auto"
          class="aspect-video w-full rounded-xl bg-black"
        >{gettext("Tu navegador no admite la reproducción de vídeo.")}</video>
        <div :if={@compatible_session.duration_ms} class="space-y-1 text-sm text-ink">
          <label for={"#{@prefix}-seek-#{@compatible_session.id}"}>{gettext("Posición")}</label>
          <input
            id={"#{@prefix}-seek-#{@compatible_session.id}"}
            type="range"
            min="0"
            max={@compatible_session.duration_ms}
            value={@compatible_session.offset_ms}
            data-compatible-seek={@compatible_session.id}
            aria-label={gettext("Ir a una posición del archivo")}
            class="w-full accent-accent"
          />
          <span data-compatible-position={@compatible_session.id}></span>
        </div>
      </div>
    </section>
    <p
      :if={@playback_error}
      id={"#{@prefix}-playback-error"}
      role="alert"
      data-reason={@playback_error_reason}
      class="mt-4 rounded-xl border border-red-300/30 bg-red-950/30 p-4 text-sm text-red-100"
    >
      {@playback_error}
    </p>
    <button
      :if={@selected_file_id && @playback_error_reason == "browser_error"}
      id={"#{@prefix}-compatible-#{@selected_file_id}"}
      type="button"
      phx-click="compatible"
      phx-value-file_id={@selected_file_id}
      class="min-h-11 rounded-xl bg-accent px-5 py-3 font-semibold text-canvas"
    >
      {gettext("Probar modo compatible")}
    </button>
    """
  end

  defp media_url(:movie, id, file), do: ~p"/movies/#{id}/media/#{file}"
  defp media_url(:episode, id, file), do: ~p"/episodes/#{id}/media/#{file}"

  defp hls_url(:movie, id, file, session),
    do: ~p"/movies/#{id}/media/#{file}/hls/#{session}/index.m3u8"

  defp hls_url(:episode, id, file, session),
    do: ~p"/episodes/#{id}/media/#{file}/hls/#{session}/index.m3u8"
end

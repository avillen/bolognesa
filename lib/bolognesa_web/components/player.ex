defmodule BolognesaWeb.Player do
  @moduledoc "Shared authorized playback controls for movie and episode pages."
  use BolognesaWeb, :html
  attr :prefix, :string, required: true
  attr :kind, :atom, required: true
  attr :entry_id, :integer, required: true
  attr :viewer_id, :integer, required: true
  attr :attempt, BolognesaWeb.LiveSupport.PlaybackAttempt, required: true
  attr :class, :string, default: "mt-10 space-y-3"
  attr :poster, :string, default: nil
  attr :retry_file_id, :integer, default: nil
  @spec player(map()) :: Phoenix.LiveView.Rendered.t()
  def player(assigns) do
    attempt = assigns.attempt

    assigns =
      assigns
      |> assign(
        playback_error: error_message(attempt.error),
        playback_error_reason: error_reason(attempt.error),
        video_id: video_id(assigns.prefix, attempt),
        video_src: video_src(assigns.kind, assigns.entry_id, attempt)
      )

    ~H"""
    <section
      :if={@attempt.file_id || @playback_error}
      id={"#{@prefix}-player"}
      class={@class}
      aria-label={gettext("Reproductor")}
    >
      <div
        id={"#{@prefix}-video-frame"}
        phx-hook="VideoPlayer"
        data-record-watched={@kind == :episode && "true"}
        data-attempt-id={@attempt.id}
        data-playback-phase={@attempt.phase}
        data-playback-probe={@attempt.probe && Jason.encode!(@attempt.probe)}
        data-transport={@attempt.plan && @attempt.plan.transport}
        data-support-evidence={
          if @attempt.plan && @attempt.plan.transport == :native_hls, do: "inferred"
        }
        data-video-id={@video_id}
        data-file-id={@attempt.file_id}
        data-recovery-scope={"#{@viewer_id}:#{@kind}:#{@entry_id}"}
        data-session-id={@attempt.session && @attempt.session.id}
        data-paused-server={to_string(@attempt.stream_paused?)}
        data-autoplay={
          to_string(@attempt.phase == :ready && (!@attempt.session || @attempt.stream_autoplay?))
        }
        data-offset-ms={@attempt.session && @attempt.session.offset_ms}
        data-duration-ms={@attempt.session && @attempt.session.duration_ms}
        data-src={!@playback_error && @video_src}
        data-playback-error={@playback_error}
        data-retry-file-id={@attempt.file_id || @retry_file_id}
        data-retry-label={gettext("Reintentar reproducción")}
        data-compatible-playback-available={to_string(@attempt.compatible_available?)}
        data-compatible-playback-label={gettext("Probar reproducción compatible")}
        class={["bolognesa-video-frame", @playback_error && "bolognesa-video-frame-error"]}
      >
        <div id={"#{@prefix}-video-ui"} phx-update="ignore">
          <media-i18n lang={Gettext.get_locale(BolognesaWeb.Gettext)}>
            <video
              id={@video_id}
              autoplay={@attempt.phase == :ready && !@attempt.session}
              controls
              playsinline
              preload="metadata"
              src={!@playback_error && !@attempt.session && @video_src}
              poster={@poster}
              class="aspect-video w-full bg-black"
            >
              {gettext("Tu navegador no admite la reproducción de vídeo.")}
            </video>
          </media-i18n>
        </div>
        <div
          :if={@attempt.phase in [:checking, :preparing] && !@playback_error}
          class="bolognesa-video-status"
        >
          <p
            :if={@attempt.phase == :checking}
            role="status"
            id={"#{@prefix}-playback-checking"}
            class="motion-safe:animate-pulse"
          >
            {gettext("Comprobando compatibilidad del navegador…")}
          </p>
          <p
            :if={@attempt.phase == :preparing}
            role="status"
            id={"#{@prefix}-playback-preparing"}
            class="motion-safe:animate-pulse"
          >
            {gettext("Preparando vídeo…")}
          </p>
        </div>
        <div :if={@playback_error} class="bolognesa-video-error">
          <p id={"#{@prefix}-playback-error"} role="alert" data-reason={@playback_error_reason}>
            {@playback_error}
          </p>
          <div class="bolognesa-video-error-actions">
            <button
              :if={@retry_file_id}
              id={"#{@prefix}-retry-playback"}
              type="button"
              phx-click="play"
              phx-value-file_id={@attempt.file_id || @retry_file_id}
              class="bolognesa-video-error-primary"
            >{gettext("Reintentar reproducción")}</button>
            <button
              :if={@attempt.compatible_available?}
              id={"#{@prefix}-playback-compatible"}
              type="button"
              phx-click="playback_compatible"
            >{gettext("Probar reproducción compatible")}</button>
            <button :if={@attempt.file_id} type="button" phx-click="playback_original">
              {gettext("Probar archivo original")}
            </button>
            <button
              :if={@attempt.file_id && !@attempt.refresh_used?}
              type="button"
              phx-click="playback_refresh"
            >
              {gettext("Actualizar análisis")}
            </button>
          </div>
          <p :if={@attempt.refresh_requested?} role="status" class="text-xs text-muted">
            {gettext("Análisis solicitado. Reintenta cuando termine.")}
          </p>
        </div>
      </div>
      <button
        :if={
          !@playback_error && @attempt.compatible_available? &&
            @attempt.phase in [:ready, :error]
        }
        id={"#{@prefix}-playback-compatible"}
        type="button"
        phx-click="playback_compatible"
        class="bolognesa-video-hint"
      >{gettext("Probar reproducción compatible")}</button>
    </section>
    """
  end

  attr :attempt, BolognesaWeb.LiveSupport.PlaybackAttempt, required: true

  @spec playback_mode(map()) :: Phoenix.LiveView.Rendered.t()
  def playback_mode(assigns) do
    ~H"""
    <p
      :if={@attempt.file_id && @attempt.phase in [:ready, :preparing] && !@attempt.error}
      id="playback-mode"
      class="text-xs leading-6 text-muted"
    >
      <span class="font-medium text-ink">{gettext("Modo de reproducción:")}</span>
      <span :if={!@attempt.session}>{gettext("Reproducción directa")}</span>
      <span :if={@attempt.session && @attempt.session.plan.mode == :remux}>{gettext(
        "Remultiplexado sin conversión"
      )}</span>
      <span :if={@attempt.session && @attempt.session.plan.mode == :video_conversion}>{gettext(
        "Transcodificación de vídeo"
      )}</span>
      <span :if={@attempt.session && @attempt.session.plan.mode == :audio_conversion}>
        {gettext("Transcodificación de audio")}
      </span>
      <span :if={@attempt.session && @attempt.session.plan.mode == :full_conversion}>
        {gettext("Transcodificación de vídeo y audio")}
      </span>
    </p>
    """
  end

  @file_unavailable [:missing, :source_changed, :source_inaccessible, :unreadable, :unsafe_entry]

  defp error_message(nil), do: nil

  defp error_message({:preparation, reason}) when reason in @file_unavailable,
    do: gettext("El archivo ya no está disponible. Revisa la biblioteca y vuelve a escanear.")

  defp error_message({:preparation, :metadata_required}),
    do: gettext("Faltan datos técnicos. Actualiza el análisis o prueba el archivo original.")

  defp error_message({:preparation, :no_video}),
    do: gettext("Este archivo no contiene una pista de vídeo reproducible.")

  defp error_message({:preparation, :detection_unknown}),
    do: gettext("No se pudo detectar la compatibilidad de este navegador.")

  defp error_message({:preparation, reason})
       when reason in [:unsupported, :unsupported_conversion],
       do: gettext("Este navegador no admite una versión segura de este vídeo.")

  defp error_message({:transcode, :interrupted}),
    do: gettext("La reproducción se ha interrumpido. Vuelve a intentarlo.")

  defp error_message(_error),
    do: gettext("No se pudo preparar esta versión. Vuelve a intentarlo.")

  defp error_reason(nil), do: nil

  defp error_reason({:preparation, reason}) when reason in @file_unavailable,
    do: "file_unavailable"

  defp error_reason({:preparation, _reason}), do: "preparation_failed"
  defp error_reason({:transcode, _stage}), do: "transcode_failed"

  defp video_id(prefix, %{session: %{id: id}}), do: "#{prefix}-video-#{id}"
  defp video_id(prefix, attempt), do: "#{prefix}-video-#{attempt.file_id}"

  defp video_src(_kind, _entry, %{phase: phase}) when phase != :ready, do: nil
  defp video_src(_kind, _entry, %{file_id: nil}), do: nil

  defp video_src(kind, entry, %{session: nil} = attempt),
    do: media_url(kind, entry, attempt.file_id)

  defp video_src(kind, entry, %{stream_ready?: true} = attempt),
    do: hls_url(kind, entry, attempt.file_id, attempt.session.id)

  defp video_src(_kind, _entry, _attempt), do: nil

  defp media_url(:movie, id, file), do: ~p"/movies/#{id}/media/#{file}"
  defp media_url(:episode, id, file), do: ~p"/episodes/#{id}/media/#{file}"

  defp hls_url(:movie, id, file, session),
    do: ~p"/movies/#{id}/media/#{file}/hls/#{session}/index.m3u8"

  defp hls_url(:episode, id, file, session),
    do: ~p"/episodes/#{id}/media/#{file}/hls/#{session}/index.m3u8"
end

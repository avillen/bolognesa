defmodule BolognesaWeb.MusicPlayer do
  @moduledoc "Document-scoped music player host rendered for authenticated browser sessions."
  use BolognesaWeb, :html

  attr :current_scope, :map, default: nil

  def host(assigns) do
    ~H"""
    <aside
      :if={@current_scope && @current_scope[:actor]}
      id="music-player-host"
      class="music-player-host"
      hidden
      aria-label={gettext("Reproductor de música")}
    >
      <audio id="music-playback" preload="metadata"></audio>
      <section id="music-player" class="music-player" aria-label={gettext("Reproductor de música")}>
        <p class="music-player-heading">{gettext("Reproductor")}</p>
        <button
          type="button"
          class="music-player-art"
          data-player-action="expand"
          aria-label={gettext("Ampliar")}
          title={gettext("Ampliar")}
          aria-expanded="false"
        >
          <img src={~p"/images/bolognesa-cat.svg"} alt="" />
        </button>
        <div class="music-player-track">
          <p id="now-playing" class="music-player-title">{gettext("Nada en reproducción")}</p>
          <p data-player-artist class="music-player-artist"></p>
          <p data-player-album class="music-player-album"></p>
        </div>
        <.transport_controls />
        <button type="button" data-player-action="retry" data-label={gettext("Reintentar")} hidden>{gettext(
          "Reintentar"
        )}</button>
        <button
          type="button"
          data-player-action="close"
          aria-label={gettext("Cerrar")}
          title={gettext("Cerrar")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
        <button
          type="button"
          data-player-action="collapse"
          aria-label={gettext("Cerrar")}
          title={gettext("Cerrar")}
          hidden
        ><.icon name="hero-chevron-down" class="size-5" /></button>
        <button
          type="button"
          class="music-queue-toggle"
          data-player-action="queue"
          data-show-label={gettext("A continuación")}
          data-hide-label={gettext("Volver al reproductor")}
          data-count-label={gettext("A continuación (%{count})", count: "__COUNT__")}
          aria-controls="music-up-next"
          aria-expanded="false"
        >{gettext("A continuación")}</button>
        <.queue_panel />
        <.player_feedback />
      </section>
    </aside>
    """
  end

  defp transport_controls(assigns) do
    ~H"""
    <button
      type="button"
      data-player-action="previous"
      data-label={gettext("Anterior")}
      aria-label={gettext("Anterior")}
      disabled
    >
      <.icon name="hero-backward-solid" class="size-5" />
    </button>
    <button
      type="button"
      data-player-action="toggle"
      data-label-play={gettext("Reproducir")}
      data-label-pause={gettext("Pausar")}
      aria-label={gettext("Reproducir")}
    >
      <span data-player-play-icon><.icon name="hero-play-solid" class="size-5" /></span>
      <span data-player-pause-icon hidden><.icon name="hero-pause-solid" class="size-5" /></span>
    </button>
    <button
      type="button"
      data-player-action="next"
      data-label={gettext("Siguiente")}
      aria-label={gettext("Siguiente")}
      disabled
    >
      <.icon name="hero-forward-solid" class="size-5" />
    </button>
    <span id="queue-position" aria-live="polite"></span>
    <span data-player-time><span data-player-elapsed></span><span class="music-time-separator"> / </span><span data-player-duration></span></span>
    <span id="queue-finished" hidden>{gettext("Sesión terminada")}</span>
    <label class="sr-only" for="music-player-seek">{gettext("Posición de reproducción")}</label>
    <input
      id="music-player-seek"
      data-player-action="seek"
      type="range"
      min="0"
      max="100"
      value="0"
      disabled
    />
    """
  end

  defp queue_panel(assigns) do
    ~H"""
    <section
      id="music-up-next"
      class="music-up-next"
      data-no-current={gettext("Nada en reproducción")}
      data-options-label={gettext("Más opciones")}
      data-remove-label={gettext("Quitar de la cola")}
      data-up-label={gettext("Subir")}
      data-down-label={gettext("Bajar")}
      hidden
      aria-label={gettext("Cola de reproducción")}
    >
      <div class="music-queue-header">
        <h2 class="music-queue-mobile-title">{gettext("A continuación")}</h2>
        <h2>{gettext("Sonando")}</h2>
        <div class="music-queue-current">
          <div class="music-queue-art" aria-hidden="true">
            <img src={~p"/images/bolognesa-cat.svg"} alt="" />
          </div><div>
            <p data-queue-current></p><p data-queue-artist></p>
          </div>
        </div>
        <div class="music-queue-list-heading">
          <h3 data-queue-heading data-label={gettext("Siguientes (%{count})", count: "__COUNT__")}>
            {gettext("A continuación")}
          </h3>
          <button type="button" data-player-action="clear-upcoming">{gettext("Vaciar cola")}</button>
        </div>
      </div>
      <div class="music-queue-scroll">
        <p data-queue-empty>{gettext("No hay canciones en espera")}</p><ol data-queue-list></ol>
      </div>
    </section>
    """
  end

  defp player_feedback(assigns) do
    ~H"""
    <p data-player-loading role="status" hidden>{gettext("Preparando reproducción…")}</p>
    <p id="audio-error" role="alert" hidden></p>
    <span hidden data-player-error="autoplay_blocked">{gettext(
      "El navegador ha bloqueado la reproducción automática. Pulsa reproducir para continuar."
    )}</span>
    <span hidden data-player-error="playback_failed">{gettext(
      "No se pudo reproducir este audio. Prueba otro formato o reintenta."
    )}</span>
    <span hidden data-player-error="unavailable">{gettext(
      "Este audio no está disponible en este momento."
    )}</span>
    <span hidden data-player-error="forbidden">{gettext(
      "No tienes permiso para reproducir este audio."
    )}</span>
    <span hidden data-player-error="empty_queue">{gettext(
      "Este álbum no tiene canciones disponibles."
    )}</span>
    """
  end
end

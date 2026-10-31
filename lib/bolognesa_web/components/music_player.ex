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
        <div class="music-player-art" aria-hidden="true">
          <img src={~p"/images/bolognesa-cat.svg"} alt="" />
        </div>
        <div class="music-player-track">
          <p id="now-playing" class="music-player-title">{gettext("Nada en reproducción")}</p>
          <p data-player-artist class="music-player-artist"></p>
        </div>
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
        <span data-player-time></span>
        <span id="queue-finished" hidden>{gettext("Álbum terminado")}</span>
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
        <button type="button" data-player-action="retry" data-label={gettext("Reintentar")} hidden>{gettext(
          "Reintentar"
        )}</button>
        <button
          type="button"
          data-player-action="expand"
          aria-label={gettext("Ampliar")}
          title={gettext("Ampliar")}
          aria-expanded="false"
        ><.icon name="hero-arrows-pointing-out" class="size-5" /></button>
        <button
          type="button"
          data-player-action="collapse"
          aria-label={gettext("Cerrar")}
          title={gettext("Cerrar")}
          hidden
        ><.icon name="hero-chevron-down" class="size-5" /></button>
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
      </section>
    </aside>
    """
  end
end

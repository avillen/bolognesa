defmodule BolognesaWeb.Music.Index.Components.TrackRow do
  @moduledoc "A track and its available playback actions."
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :track, :any, required: true
  attr :browse_kind, :atom, required: true
  attr :album_id, :integer, default: nil
  attr :active_library_id, :integer, default: nil

  def track_row(assigns) do
    ~H"""
    <article
      id={@id}
      data-state={@track.state}
      data-track-id={@track.track_id}
      data-file-id={@track.id}
      class="music-track-row"
    >
      <div class="music-track-art" aria-hidden="true">
        <span class="music-track-note">{@track.track_number || ""}</span>
        <span class="music-equalizer" aria-hidden="true"><i></i><i></i><i></i></span>
      </div>
      <div class="music-track-copy">
        <h2 class="font-semibold break-words">{@track.title}</h2><p class="text-sm break-words">
          {@track.artist}
          <%= if @browse_kind != :album do %>
            · {@track.album}
          <% end %>
        </p><p class="music-track-meta">
          <span class="music-track-mobile-duration">{@track.duration}</span>
          <span class="music-track-last-played">{@track.last_played}</span>
          <span class="music-playing-label">{gettext("Sonando")}</span>
          <span class="music-paused-label">{gettext("En pausa")}</span><span class="music-track-state">{@track.state_label}</span>
        </p>
      </div>
      <span class="music-track-duration">{@track.duration}</span>
      <.track_actions
        track={@track}
        browse_kind={@browse_kind}
        album_id={@album_id}
        active_library_id={@active_library_id}
      />
    </article>
    """
  end

  attr :track, :any, required: true
  attr :browse_kind, :atom, required: true
  attr :album_id, :integer, default: nil
  attr :active_library_id, :integer, default: nil

  defp track_actions(assigns) do
    ~H"""
    <button
      :if={@track.state == :ready}
      type="button"
      data-music-action="append-track"
      data-track-id={@track.track_id}
      data-file-id={@track.id}
      class="music-track-queue"
      aria-label={gettext("Añadir %{title} a la cola", title: @track.title)}
      title={gettext("Añadir a la cola")}
    ><.icon name="hero-plus" class="size-5" /></button>
    <details
      :if={@track.state == :ready}
      class="music-action-menu"
      phx-mounted={JS.ignore_attributes("open")}
    >
      <summary aria-label={gettext("Más opciones")} title={gettext("Más opciones")}>
        <.icon name="hero-ellipsis-horizontal" class="size-5" />
      </summary>
      <button
        :if={@track.state == :ready}
        type="button"
        data-music-action="play-next"
        data-track-id={@track.track_id}
        data-file-id={@track.id}
        class="music-track-queue"
        aria-label={gettext("Reproducir %{title} a continuación", title: @track.title)}
        title={gettext("Reproducir a continuación")}
      ><.icon name="hero-forward-solid" class="size-5" />{gettext("Reproducir a continuación")}</button>
      <button
        :if={@browse_kind == :album && @track.state == :ready}
        type="button"
        data-music-action="track-only"
        data-track-id={@track.track_id}
        data-file-id={@track.id}
        class="music-track-queue"
        aria-label={gettext("Reproducir solo %{title}", title: @track.title)}
        title={gettext("Reproducir solo esta canción")}
      ><.icon name="hero-play-solid" class="size-5" />{gettext("Reproducir solo esta canción")}</button>
    </details>
    <button
      :if={@track.state == :ready}
      id={"play-track-#{@track.track_id}"}
      type="button"
      data-music-action="track"
      data-track-id={@track.track_id}
      data-file-id={@track.id}
      data-album-id={@browse_kind == :album && @album_id}
      data-library-id={@browse_kind == :album && @active_library_id}
      class="music-track-play"
      aria-label={gettext("Reproducir %{title}", title: @track.title)}
      title={gettext("Reproducir %{title}", title: @track.title)}
      data-play-label={gettext("Reproducir %{title}", title: @track.title)}
      data-pause-label={gettext("Pausar %{title}", title: @track.title)}
    >
      <.icon name="hero-play-solid" class="music-play-icon size-5" />
      <.icon name="hero-pause-solid" class="music-pause-icon size-5" />
    </button>
    <button
      :if={@track.state == :import_failed}
      type="button"
      phx-click="retry-import"
      phx-value-file_id={@track.id}
      class="min-h-11 rounded-lg border border-border-strong px-4 py-2 text-ink hover:bg-raised disabled:opacity-50"
    >{gettext("Reintentar importación")}</button>
    <.link
      :if={@track.state == :inspection_failed}
      navigate={~p"/libraries"}
      class="min-h-11 rounded-lg border border-border-strong px-4 py-2 text-ink hover:bg-raised disabled:opacity-50"
    >{gettext("Reanalizar en bibliotecas")}</.link>
    """
  end
end

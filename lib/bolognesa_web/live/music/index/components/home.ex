defmodule BolognesaWeb.Music.Index.Components.Home do
  @moduledoc "Music home with recent listening and collection entry points."
  use BolognesaWeb, :html

  attr :albums, :list, required: true
  attr :status, :atom, required: true
  attr :library_params, :map, required: true
  attr :library_id, :integer, default: nil

  @spec home(map()) :: Phoenix.LiveView.Rendered.t()
  def home(assigns) do
    ~H"""
    <section id="music-last-listened" aria-labelledby="music-last-listened-title">
      <div class="music-recent-section-heading">
        <h2 id="music-last-listened-title" class="text-xl font-semibold">
          {gettext("Últimos discos escuchados")}
        </h2>
        <p>{gettext("Vuelve a lo que te apetezca")}</p>
      </div>
      <p :if={@status == :loading} role="status" class="music-feedback">
        {gettext("Cargando últimas escuchas…")}
      </p>
      <p :if={@status == :empty} id="music-last-listened-empty" class="music-feedback">
        {gettext("Todavía no has escuchado ningún álbum.")}
      </p>
      <div
        :if={@status == :error}
        id="music-last-listened-error"
        role="alert"
        class="music-feedback music-feedback-error"
      >
        <p>{gettext("No se pudieron cargar las últimas escuchas.")}</p>
        <button type="button" phx-click="retry-last-listened" class="min-h-11 text-accent">
          {gettext("Reintentar")}
        </button>
      </div>
      <div :if={@status == :ready} class="music-recent-grid">
        <article :for={album <- @albums} id={"recent-album-#{album.id}"} class="music-recent-card">
          <.link
            class="music-recent-heading recent-album-open"
            patch={~p"/music?#{Map.merge(@library_params, %{view: :album, album_id: album.id})}"}
            aria-label={gettext("Ver %{title}", title: album.title)}
          >
            <div class="music-detail-art" aria-hidden="true">
              <.icon name="hero-musical-note" class="size-8" />
            </div>
            <div class="min-w-0">
              <h3 class="text-lg font-semibold break-words">{album.title}</h3>
              <p :if={album.artist} class="text-sm text-muted break-words">{album.artist}</p>
            </div>
          </.link>
          <div class="music-recent-footer">
            <div class="music-recent-meta">
              <p class="music-recent-track">
                {gettext("Última canción escuchada:")} <strong>{album.track_title}</strong>
              </p>
              <p class="music-recent-date">
                {gettext("Última reproducción:")}
                <time datetime={DateTime.to_iso8601(album.last_played_at)}>
                  {Calendar.strftime(album.last_played_at, "%d/%m/%Y")}
                </time>
              </p>
              <p :if={!album.track_available?} class="text-sm text-muted">
                {gettext("La última canción ya no está disponible. Abre el álbum para elegir otra.")}
              </p>
            </div>
            <div class="music-recent-actions">
              <button
                id={"recent-continue-#{album.id}"}
                type="button"
                data-music-action="resume-album"
                data-album-id={album.id}
                data-library-id={@library_id}
                data-track-id={album.track_id}
                data-file-id={album.file_id}
                data-open-album="true"
                disabled={!album.track_available?}
                aria-label={gettext("Continuar %{title}", title: album.title)}
                class="music-recent-play"
              ><.icon name="hero-play-solid" class="size-5" /><span class="sr-only">{gettext(
                "Continuar"
              )}</span></button>
              <button
                id={"recent-play-#{album.id}"}
                type="button"
                data-music-action="album"
                data-album-id={album.id}
                data-library-id={@library_id}
                data-open-album="true"
                aria-label={gettext("Reproducir %{title} de nuevo", title: album.title)}
                class="music-recent-replay"
              ><.icon name="hero-arrow-uturn-left" class="size-5" /><span class="sr-only">{gettext(
                "Reproducir de nuevo"
              )}</span></button>
            </div>
          </div>
        </article>
      </div>
    </section>
    <section id="music-explore" aria-labelledby="music-explore-title">
      <h2 id="music-explore-title" class="mb-4 text-xl font-semibold">
        {gettext("Explorar tu música")}
      </h2>
      <div class="music-explore-grid">
        <.link
          :for={
            {kind, title, icon} <- [
              {:artists, gettext("Artistas"), "hero-user-group"},
              {:albums, gettext("Álbumes"), "hero-musical-note"},
              {:tracks, gettext("Canciones"), "hero-list-bullet"}
            ]
          }
          patch={~p"/music?#{Map.put(@library_params, :view, kind)}"}
          class="flex min-h-20 items-center gap-4 rounded-xl border border-border-strong bg-surface p-5 font-semibold text-ink hover:bg-raised"
        ><.icon name={icon} class="size-6 text-accent-soft" />{title}<.icon
          name="hero-chevron-right"
          class="ml-auto size-5"
        /></.link>
      </div>
    </section>
    """
  end
end

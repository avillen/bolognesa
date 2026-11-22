defmodule BolognesaWeb.Music.Index.Components.Home do
  @moduledoc "Music home with recent listening."
  use BolognesaWeb, :html

  alias BolognesaWeb.Music.Index.Components.Artwork

  attr :albums, :list, required: true
  attr :status, :atom, required: true
  attr :library_params, :map, required: true
  attr :library_id, :integer, default: nil

  @spec home(map()) :: Phoenix.LiveView.Rendered.t()
  def home(assigns) do
    ~H"""
    <section id="music-last-listened" aria-labelledby="music-last-listened-title">
      <div class="music-recent-section-heading">
        <h2 id="music-last-listened-title">
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
      <Alert.alert
        :if={@status == :error}
        id="music-last-listened-error"
        variant="destructive"
        class="flex flex-wrap items-center justify-between gap-3"
      >
        <Alert.alert_description>
          <p>{gettext("No se pudieron cargar las últimas escuchas.")}</p>
        </Alert.alert_description>
        <Button.button
          type="button"
          variant="outline"
          phx-click="retry-last-listened"
          class="text-foreground"
        >
          {gettext("Reintentar")}
        </Button.button>
      </Alert.alert>
      <div :if={@status == :ready} class="music-recent-grid">
        <.recent_album_card
          :for={album <- @albums}
          album={album}
          library_params={@library_params}
          library_id={@library_id}
        />
      </div>
    </section>
    """
  end

  attr :album, :any, required: true
  attr :library_params, :map, required: true
  attr :library_id, :integer, default: nil

  defp recent_album_card(assigns) do
    assigns =
      assign(
        assigns,
        :play_class,
        "rounded-full shadow-lg shadow-primary/30 hover:bg-accent-hover motion-safe:hover:scale-105 motion-reduce:transition-none disabled:shadow-none"
      )

    ~H"""
    <Card.card tag="article" id={"recent-album-#{@album.id}"} class="music-recent-card">
      <.link
        class="music-recent-heading recent-album-open"
        patch={~p"/music?#{Map.merge(@library_params, %{view: :album, album_id: @album.id})}"}
        aria-label={gettext("Ver %{title}", title: @album.title)}
      >
        <Artwork.artwork id={@album.id} title={@album.title} />
        <div class="music-recent-copy">
          <h3>{@album.title}</h3>
          <p :if={@album.artist}>{@album.artist}</p>
        </div>
      </.link>
      <div class="music-recent-footer">
        <div class="music-recent-meta">
          <p class="music-recent-track">
            {gettext("Última canción escuchada:")} <strong>{@album.track_title}</strong>
          </p>
          <p class="music-recent-date">
            {gettext("Última reproducción:")}
            <time datetime={DateTime.to_iso8601(@album.last_played_at)}>
              {Calendar.strftime(@album.last_played_at, "%d/%m/%Y")}
            </time>
          </p>
          <p :if={!@album.track_available?} class="text-sm text-muted">
            {gettext("La última canción ya no está disponible. Abre el álbum para elegir otra.")}
          </p>
        </div>
        <div class="music-recent-actions">
          <Button.button
            :if={!@album.restart?}
            id={"recent-continue-#{@album.id}"}
            type="button"
            data-music-action="resume-album"
            data-album-id={@album.id}
            data-library-id={@library_id}
            data-track-id={@album.track_id}
            data-file-id={@album.file_id}
            disabled={!@album.track_available?}
            aria-label={gettext("Continuar %{title}", title: @album.title)}
            size="icon"
            class={@play_class}
          ><.icon name="hero-play-solid" class="size-5" /><span class="sr-only">{gettext("Continuar")}</span></Button.button>
          <Button.button
            id={"recent-play-#{@album.id}"}
            type="button"
            data-music-action="album"
            data-album-id={@album.id}
            data-library-id={@library_id}
            aria-label={gettext("Reproducir %{title} de nuevo", title: @album.title)}
            variant={if @album.restart?, do: "default", else: "outline"}
            size="icon"
            class={if @album.restart?, do: @play_class, else: "rounded-full"}
          ><.icon
            name={if @album.restart?, do: "hero-play-solid", else: "hero-arrow-uturn-left"}
            class="size-5"
          /><span class="sr-only">{gettext("Reproducir de nuevo")}</span></Button.button>
        </div>
      </div>
    </Card.card>
    """
  end
end

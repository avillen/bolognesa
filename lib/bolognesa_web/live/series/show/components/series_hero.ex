defmodule BolognesaWeb.Series.Show.Components.SeriesHero do
  @moduledoc false
  use BolognesaWeb, :html

  attr :series, :any, required: true
  attr :total, :integer, required: true

  @spec series_hero(map()) :: Phoenix.LiveView.Rendered.t()
  def series_hero(assigns) do
    ~H"""
    <div class="media-hero">
      <div :if={@series.backdrop_path} class="media-backdrop">
        <img
          id={"series-backdrop-#{@series.id}"}
          phx-hook="ImageFallback"
          phx-update="ignore"
          src={"https://image.tmdb.org/t/p/w780#{@series.backdrop_path}"}
          alt={gettext("Imagen de %{value0}", value0: @series.title)}
          class="size-full object-cover"
        />
      </div>
      <div class="media-hero-content">
        <div class="media-hero-poster">
          <div class="media-art-fallback" aria-hidden="true">
            <.icon name="hero-tv" class="size-10" />
          </div>
          <img
            :if={@series.poster_path}
            id={"series-detail-poster-#{@series.id}"}
            phx-hook="ImageFallback"
            phx-update="ignore"
            src={"https://image.tmdb.org/t/p/w342#{@series.poster_path}"}
            alt={gettext("Cartel de %{value0}", value0: @series.title)}
            class="absolute inset-0 size-full object-cover"
          />
        </div>
        <div class="media-hero-copy">
          <p class="media-eyebrow">{gettext("Series")}</p>
          <h1 id="series-title" class="text-4xl font-semibold text-ink">
            {@series.title}
          </h1>
          <p class="mt-4 flex flex-wrap items-center gap-3 text-sm text-muted">
            <span>{@series.year || gettext("Año desconocido")}</span>
            <span aria-hidden="true" class="text-accent">/</span>
            <span>{ngettext(
              "%{count} temporada en tu biblioteca",
              "%{count} temporadas en tu biblioteca",
              @total
            )}</span>
          </p>
        </div>
      </div>
    </div>
    """
  end
end

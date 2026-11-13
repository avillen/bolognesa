defmodule BolognesaWeb.Series.Index.Components.SeriesCard do
  @moduledoc false
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :series, :any, required: true
  attr :series_params, :map, required: true

  @spec series_card(map()) :: Phoenix.LiveView.Rendered.t()
  def series_card(assigns) do
    ~H"""
    <article
      id={@id}
      class="poster-card series-catalog-card"
    >
      <.link navigate={~p"/series/#{@series.id}?#{@series_params}"} class="media-catalog-link">
        <div class="poster-art media-poster-art">
          <div class="media-art-fallback" aria-hidden="true">
            <.icon name="hero-tv" class="size-9" />
            <span>{@series.title}</span>
          </div>
          <img
            :if={@series.poster_path}
            id={"series-poster-#{@series.id}"}
            phx-hook="ImageFallback"
            phx-update="ignore"
            src={"https://image.tmdb.org/t/p/w342#{@series.poster_path}"}
            alt={gettext("Cartel de %{value0}", value0: @series.title)}
            loading="lazy"
            class="absolute inset-0 size-full object-cover"
          />
          <span class="media-year">{@series.year || gettext("Año desconocido")}</span>
        </div>
        <h2 class="mt-4 text-base font-semibold leading-snug text-ink">{@series.title}</h2>
      </.link>
      <p class="mt-2 text-xs leading-5 text-muted">
        {ngettext(
          "%{count} episodio disponible",
          "%{count} episodios disponibles",
          @series.available_episode_count
        )}
      </p>
    </article>
    """
  end
end

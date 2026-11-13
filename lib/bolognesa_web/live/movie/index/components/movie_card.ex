defmodule BolognesaWeb.Movie.Index.Components.MovieCard do
  @moduledoc false
  use BolognesaWeb, :html

  attr :dom_id, :string, required: true
  attr :movie, :map, required: true
  attr :library_params, :map, required: true

  def card(assigns) do
    ~H"""
    <div
      id={@dom_id}
      class="poster-card"
    >
      <.link
        navigate={~p"/movies/#{@movie.id}?#{@library_params}"}
        id={"movie-link-#{@movie.id}"}
        class="media-catalog-link"
      >
        <div class="poster-art media-poster-art">
          <div class="media-art-fallback" aria-hidden="true">
            <.icon name="hero-film" class="size-9" />
            <span>{@movie.title}</span>
          </div>
          <img
            :if={@movie.poster_path}
            id={"movie-poster-#{@movie.id}"}
            phx-hook="ImageFallback"
            phx-update="ignore"
            src={"https://image.tmdb.org/t/p/w500#{@movie.poster_path}"}
            alt={gettext("Cartel de %{value0}", value0: @movie.title)}
            loading="lazy"
            class="absolute inset-0 size-full object-cover"
          />
          <span class="media-year">{@movie.year || gettext("Año desconocido")}</span>
        </div>
        <div class="pt-4">
          <h2 class="text-base font-semibold leading-snug text-ink">{@movie.title}</h2>
          <p class="mt-1 text-xs text-muted">
            {ngettext(
              "%{count} versión",
              "%{count} versiones",
              @movie.version_count
            )}
          </p>
          <p class="mt-1 text-xs font-medium text-muted">
            {ngettext("%{count} disponible", "%{count} disponibles", @movie.available_count)}
          </p>
        </div>
      </.link>
    </div>
    """
  end
end

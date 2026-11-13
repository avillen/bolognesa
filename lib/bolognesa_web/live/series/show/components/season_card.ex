defmodule BolognesaWeb.Series.Show.Components.SeasonCard do
  @moduledoc false
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :season, :any, required: true
  attr :series_params, :map, required: true

  @spec season_card(map()) :: Phoenix.LiveView.Rendered.t()
  def season_card(assigns) do
    ~H"""
    <article id={@id}>
      <.link
        navigate={~p"/series/seasons/#{@season.id}?#{@series_params}"}
        class="series-season-card"
      >
        <div class="series-season-art">
          <span aria-hidden="true">{String.pad_leading(to_string(@season.number), 2, "0")}</span>
          <img
            :if={@season.poster_path}
            id={"season-poster-#{@season.id}"}
            phx-hook="ImageFallback"
            phx-update="ignore"
            src={"https://image.tmdb.org/t/p/w185#{@season.poster_path}"}
            alt=""
            loading="lazy"
            class="absolute inset-0 size-full object-cover"
          />
        </div>
        <div class="min-w-0 flex-1">
          <h3 class="text-base font-semibold text-ink">
            {if @season.number == 0,
              do: gettext("Especiales"),
              else: gettext("Temporada %{value0}", value0: @season.number)}
          </h3>
          <p class="mt-2 text-sm leading-6 text-muted">
            {ngettext(
              "%{count} episodio identificado",
              "%{count} episodios identificados",
              @season.episode_count
            )}
          </p>
        </div>
        <.icon name="hero-chevron-right" class="size-5 shrink-0 text-accent-soft" />
      </.link>
    </article>
    """
  end
end

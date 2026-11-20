defmodule BolognesaWeb.Series.Index.Components.ContinueTile do
  @moduledoc "Landscape Continue tile; the first one leads the marquee with its synopsis."
  use BolognesaWeb, :html
  alias BolognesaWeb.Series.Components.ContinueLink

  attr :id, :string, required: true
  attr :series, :any, required: true
  attr :target, :any, required: true
  attr :series_params, :map, required: true
  attr :lead?, :boolean, default: false

  @spec continue_tile(map()) :: Phoenix.LiveView.Rendered.t()
  def continue_tile(assigns) do
    assigns = assign(assigns, :art, assigns.series.backdrop_path || assigns.series.poster_path)

    ~H"""
    <article id={@id} class={["series-continue-tile", @lead? && "is-lead"]}>
      <div class="series-continue-art" aria-hidden="true">
        <.icon name="hero-tv" class="size-8" />
        <img
          :if={@art}
          id={"#{@id}-art"}
          phx-hook="ImageFallback"
          phx-update="ignore"
          src={"https://image.tmdb.org/t/p/#{if @lead?, do: "w1280", else: "w780"}#{@art}"}
          alt=""
          loading="lazy"
        />
      </div>
      <div class="series-continue-copy">
        <h3>
          <.link navigate={~p"/series/#{@series.id}?#{@series_params}"}>{@series.title}</.link>
        </h3>
        <p :if={@lead? && @series.overview} class="series-continue-overview">{@series.overview}</p>
        <ContinueLink.continue_link
          id={"recent-series-continue-#{@series.id}"}
          target={@target}
          series_params={@series_params}
          class={if @lead?, do: "media-primary-action", else: "series-continue-action"}
        />
      </div>
    </article>
    """
  end
end

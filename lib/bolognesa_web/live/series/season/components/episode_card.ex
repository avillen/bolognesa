defmodule BolognesaWeb.Series.Season.Components.EpisodeCard do
  @moduledoc false
  use BolognesaWeb, :html

  alias BolognesaWeb.Series.Navigation

  attr :id, :string, required: true
  attr :episode, :any, required: true
  attr :series_params, :map, required: true
  attr :page, :integer, required: true

  @spec episode_card(map()) :: Phoenix.LiveView.Rendered.t()
  def episode_card(assigns) do
    ~H"""
    <article id={@id} class="series-episode-card">
      <.link
        navigate={
          ~p"/episodes/#{@episode.id}?#{Navigation.episode_target_params(@series_params, @page, @episode)}"
        }
        class="series-episode-detail"
        aria-labelledby={"episode-label-#{@episode.key}"}
        aria-describedby={
          @episode.available_version_count == 0 && "episode-availability-#{@episode.key}"
        }
      >
        <div class="series-episode-art">
          <.icon name="hero-film" class="size-8 text-muted" />
          <img
            :if={@episode.still_path}
            id={"episode-still-#{@episode.key}"}
            phx-hook="ImageFallback"
            phx-update="ignore"
            src={"https://image.tmdb.org/t/p/w300#{@episode.still_path}"}
            alt=""
            loading="lazy"
            class="absolute inset-0 size-full object-cover"
          />
          <span class="series-episode-number">{String.pad_leading(
            to_string(@episode.number),
            2,
            "0"
          )}</span>
        </div>
        <div class="series-episode-copy">
          <h2 id={"episode-label-#{@episode.key}"} class="font-semibold leading-snug text-ink">
            {@episode.number}. {if @episode.part_number,
              do:
                gettext("%{title} (Parte %{number})",
                  title: @episode.title,
                  number: @episode.part_number
                ),
              else: @episode.title}
          </h2>
          <p :if={@episode.overview} class="series-episode-overview">{@episode.overview}</p>
          <p
            :if={@episode.available_version_count == 0}
            id={"episode-availability-#{@episode.key}"}
            class="mt-3 flex items-start gap-2 text-xs leading-5 text-muted"
          >
            {gettext("No disponible")}
          </p>
        </div>
      </.link>
      <.link
        :if={@episode.available_version_count > 0}
        id={"episode-play-#{@episode.key}"}
        navigate={
          ~p"/episodes/#{@episode.id}?#{Navigation.episode_target_params(@series_params, @page, @episode)}"
        }
        class="series-episode-play"
        aria-label={
          gettext("Reproducir %{title}",
            title:
              if(@episode.part_number,
                do:
                  gettext("%{title} (Parte %{number})",
                    title: @episode.title,
                    number: @episode.part_number
                  ),
                else: @episode.title
              )
          )
        }
      >
        <.icon name="hero-play-solid" class="size-4" /> {gettext("Reproducir")}
      </.link>
    </article>
    """
  end
end

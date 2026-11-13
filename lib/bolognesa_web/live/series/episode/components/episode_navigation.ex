defmodule BolognesaWeb.Series.Episode.Components.EpisodeNavigation do
  @moduledoc false
  use BolognesaWeb, :html

  alias BolognesaWeb.Series.Navigation

  attr :previous_target, :any, required: true
  attr :next_target, :any, required: true
  attr :series_params, :map, required: true
  attr :season_params, :map, required: true

  @spec episode_navigation(map()) :: Phoenix.LiveView.Rendered.t()
  def episode_navigation(assigns) do
    ~H"""
    <nav
      id="episode-navigation"
      class="episode-navigation"
      aria-label={gettext("Navegación entre episodios")}
    >
      <.link
        :if={@previous_target}
        id="episode-previous"
        rel="prev"
        patch={
          ~p"/episodes/#{@previous_target.id}?#{Navigation.episode_target_params(@series_params, Map.get(@season_params, :page, 1), @previous_target)}"
        }
        aria-label={gettext("Anterior episodio")}
      >
        <span aria-hidden="true">←</span>
        <span class="sm:hidden">{gettext("Anterior")}</span><span class="hidden sm:inline">{gettext(
          "Anterior episodio"
        )}</span>
      </.link>
      <.link
        :if={@next_target}
        id="episode-next"
        rel="next"
        patch={
          ~p"/episodes/#{@next_target.id}?#{Navigation.episode_target_params(@series_params, Map.get(@season_params, :page, 1), @next_target)}"
        }
        aria-label={gettext("Siguiente episodio")}
      >
        <span class="sm:hidden">{gettext("Siguiente")}</span><span class="hidden sm:inline">{gettext(
          "Siguiente episodio"
        )}</span>
        <span aria-hidden="true">→</span>
      </.link>
    </nav>
    """
  end
end

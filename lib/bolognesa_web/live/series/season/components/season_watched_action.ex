defmodule BolognesaWeb.Series.Season.Components.SeasonWatchedAction do
  @moduledoc false
  use BolognesaWeb, :html

  @spec season_watched_action(map()) :: Phoenix.LiveView.Rendered.t()
  def season_watched_action(assigns) do
    ~H"""
    <button
      id="season-watched-action"
      type="button"
      phx-click="mark_season_watched"
      class="media-secondary-action mt-4"
    >
      <.icon name="hero-eye" class="size-4" /> {gettext("Marcar temporada como vista")}
    </button>
    """
  end
end

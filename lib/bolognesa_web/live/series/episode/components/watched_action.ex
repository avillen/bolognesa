defmodule BolognesaWeb.Series.Episode.Components.WatchedAction do
  @moduledoc false
  use BolognesaWeb, :html

  attr :watched?, :boolean, required: true

  @spec watched_action(map()) :: Phoenix.LiveView.Rendered.t()
  def watched_action(assigns) do
    ~H"""
    <button
      id="episode-watched-action"
      type="button"
      phx-click={if @watched?, do: "unmark_watched", else: "mark_watched"}
      class="media-secondary-action mt-4"
    >
      <.icon name={if @watched?, do: "hero-eye-slash", else: "hero-eye"} class="size-4" />
      {if @watched?, do: gettext("Marcar como no visto"), else: gettext("Marcar como visto")}
    </button>
    """
  end
end

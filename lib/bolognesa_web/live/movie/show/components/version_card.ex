defmodule BolognesaWeb.Movie.Show.Components.VersionCard do
  @moduledoc false
  use BolognesaWeb, :html

  attr :version, :map, required: true
  attr :selected_file_id, :any, required: true

  def card(assigns) do
    ~H"""
    <div
      id={"movie-version-#{@version.id}"}
      class="movie-version-card"
    >
      <div class="movie-version-summary">
        <span class="movie-version-icon" aria-hidden="true"><.icon
          name="hero-film"
          class="size-6"
        /></span>
        <div class="min-w-0">
          <p class="font-semibold text-ink">{gettext("Versión")} {@version.id}</p>
          <span
            :if={@version.id == @selected_file_id}
            id={"movie-selected-#{@version.id}"}
            class="movie-selected"
          >{gettext("Seleccionada")}</span>
          <p class="mt-1 text-xs text-muted">
            {if @version.origin == :manual,
              do: gettext("Identificación manual"),
              else: gettext("Identificación automática")}{if @version.needs_review,
              do: gettext(" · Revisar"),
              else: ""}
          </p>
        </div>
      </div>
      <span class={[
        "movie-version-availability",
        @version.availability == :available && "is-available"
      ]}>{if @version.availability ==
               :available,
             do: gettext("Disponible"),
             else: gettext("No disponible")}</span>
      <div class="movie-version-actions">
        <button
          :if={@version.availability == :available}
          id={"movie-play-#{@version.id}"}
          type="button"
          phx-click="play"
          phx-value-file_id={@version.id}
          class="media-primary-action"
        >
          {gettext("Reproducir")}
        </button>
        <.link
          navigate={~p"/movies/review?#{%{file_id: @version.id}}"}
          id={"movie-correct-#{@version.id}"}
          class="media-secondary-action"
        >{gettext("Corregir")}</.link>
      </div>
    </div>
    """
  end
end

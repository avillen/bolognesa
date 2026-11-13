defmodule BolognesaWeb.Series.Episode.Components.VersionCard do
  @moduledoc false
  use BolognesaWeb, :html

  attr :version, :any, required: true
  attr :parts, :list, required: true
  attr :selected_file_id, :any, required: true

  @spec version_card(map()) :: Phoenix.LiveView.Rendered.t()
  def version_card(assigns) do
    ~H"""
    <article
      id={"episode-version-#{@version.id}"}
      class="episode-version"
    >
      <div class="flex flex-wrap items-center gap-2">
        <h3 class="text-sm font-semibold text-ink">
          <span :if={is_nil(@version.part_number) && @parts != []}>{gettext("Episodio completo")} · </span>{@version.format ||
            gettext("Archivo de vídeo")} · {Float.round(
            @version.size_bytes / 1_048_576,
            1
          )} MB
        </h3>
        <span
          :if={@version.id == @selected_file_id}
          id={"episode-selected-#{@version.id}"}
          class="episode-selected"
        >{gettext("Seleccionada")}</span>
        <span :if={@version.availability != :available} class="text-xs text-muted">{gettext(
          "No disponible"
        )}</span>
      </div>
      <details
        id={"episode-technical-#{@version.id}"}
        class="episode-technical"
        phx-mounted={JS.ignore_attributes("open")}
      >
        <summary>{gettext("Detalles del archivo")}</summary>
        <p :if={@version.codecs != []}>{Enum.join(@version.codecs, " / ")}</p>
        <p :if={@version.duration_ms}>
          {gettext("Duración:")} {div(@version.duration_ms, 60_000)} min
        </p>
        <p :if={length(@version.episode_numbers) > 1}>
          {gettext("Contiene episodios")} {Enum.join(@version.episode_numbers, ", ")}
        </p>
        <p>
          {if @version.origin == :manual,
            do: gettext("Identificación manual"),
            else: gettext("Identificación automática")}{if @version.needs_review?,
            do: gettext(" · Revisar"),
            else: ""}
        </p>
        <.link
          navigate={~p"/series/review?#{%{file_id: @version.id}}"}
          id={"episode-correct-#{@version.id}"}
          class="inline-flex min-h-11 items-center text-accent-soft"
        >
          {gettext("Corregir identificación")}
        </.link>
      </details>
      <button
        :if={@version.availability == :available && @version.id != @selected_file_id}
        id={"episode-play-#{@version.id}"}
        type="button"
        phx-click="play"
        phx-value-file_id={@version.id}
        class="series-episode-play"
      >
        {gettext("Elegir esta versión")}
      </button>
    </article>
    """
  end
end

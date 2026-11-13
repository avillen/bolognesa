defmodule BolognesaWeb.Series.Review.Components.ReviewItem do
  @moduledoc false
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :item, :any, required: true
  attr :page, :integer, required: true
  attr :saving?, :boolean, required: true

  @spec review_item(map()) :: Phoenix.LiveView.Rendered.t()
  def review_item(assigns) do
    ~H"""
    <article
      id={@id}
      class="rounded-2xl border border-border bg-surface p-4"
    >
      <p class="font-semibold break-all">{@item.filename}</p>
      <p>{state_label(@item.state)} · {failure_label(@item.failure_reason)}</p>
      <p :if={@item.episode_numbers != []}>
        {@item.series_title} {gettext("· temporada")} {@item.season_number} {gettext(
          "· episodios"
        )} {Enum.join(
          @item.episode_numbers,
          ", "
        )}
      </p>
      <p :if={@item.availability == :missing}>{gettext("Archivo no disponible")}</p>
      <.link
        :if={!@saving?}
        patch={~p"/series/review?page=#{@page}&file_id=#{@item.file_id}"}
        class="min-h-11 inline-flex items-center justify-center rounded-xl px-4 py-3 font-medium transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-wait disabled:opacity-50 border border-border-strong text-accent-soft"
        aria-disabled={@saving?}
      >{gettext("Corregir")}</.link>
      <button
        phx-click="retry"
        phx-value-file_id={@item.file_id}
        disabled={@saving?}
        class="min-h-11 inline-flex items-center justify-center rounded-xl px-4 py-3 font-medium transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-wait disabled:opacity-50 text-accent-soft hover:bg-raised"
      >{gettext("Reintentar identificación")}</button>
    </article>
    """
  end

  defp state_label(:pending), do: gettext("Pendiente")
  defp state_label(:failed), do: "Error"
  defp state_label(:unmatched), do: gettext("Sin coincidencia")
  defp state_label(:manual_unidentified), do: gettext("Sin identificar manualmente")
  defp state_label(_), do: gettext("Revisar identificación")

  defp failure_label("incomplete_episodes"),
    do: gettext("TMDb no contiene todos los episodios indicados")

  defp failure_label("unusable_name"), do: gettext("Nombre de archivo no interpretable")
  defp failure_label("not_configured"), do: gettext("TMDb sin configurar")
  defp failure_label("rate_limited"), do: gettext("TMDb limitó las solicitudes")
  defp failure_label(_), do: gettext("La identificación necesita revisión")
end

defmodule BolognesaWeb.Movie.Review.Components.ReviewItem do
  @moduledoc false
  use BolognesaWeb, :html

  attr :dom_id, :string, required: true
  attr :item, :map, required: true

  def item(assigns) do
    ~H"""
    <article
      id={@dom_id}
      class="rounded-2xl border border-border bg-surface p-5"
    >
      <h2 class="break-words font-semibold text-ink">{@item.filename}</h2>
      <p class="mt-2 text-xs text-muted">
        {state_label(@item.state)} · {if @item.availability == :available,
          do: gettext("Disponible"),
          else: gettext("Ausente")}
      </p>
      <p :if={@item.movie_title} class="mt-2 text-sm text-accent-soft">{@item.movie_title}</p>
      <p
        :if={@item.failure_reason}
        id={"review-failure-#{@item.file_id}"}
        class="mt-2 text-sm text-red-200"
      >
        {failure_label(@item.failure_reason)}
      </p>
      <div class="mt-4 flex flex-wrap gap-2">
        <button
          id={"review-select-#{@item.file_id}"}
          type="button"
          phx-click="select"
          phx-value-file_id={@item.file_id}
          class="min-h-11 rounded-xl bg-accent px-4 text-sm font-semibold text-canvas transition hover:bg-accent-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >{gettext("Corregir")}</button>
        <button
          :if={@item.state != :manual_unidentified}
          id={"review-retry-#{@item.file_id}"}
          type="button"
          phx-click="retry"
          phx-value-file_id={@item.file_id}
          class="min-h-11 rounded-xl border border-border-strong px-4 text-sm text-ink transition hover:border-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >{gettext("Reintentar")}</button>
      </div>
    </article>
    """
  end

  defp state_label(:pending), do: gettext("Pendiente")
  defp state_label(:failed), do: "Error"
  defp state_label(:unmatched), do: gettext("Sin coincidencia")
  defp state_label(:manual_unidentified), do: gettext("Sin identificar manualmente")
  defp state_label(:automatic), do: gettext("Revisar coincidencia")
  defp state_label(_), do: gettext("Revisión")

  defp failure_label("not_configured"), do: gettext("TMDb sin configurar")
  defp failure_label("rate_limited"), do: gettext("TMDb limitó las solicitudes")
  defp failure_label("provider_unavailable"), do: gettext("TMDb no disponible")
  defp failure_label("unauthorized"), do: gettext("Token de TMDb rechazado")
  defp failure_label("unusable_name"), do: gettext("Nombre de archivo no interpretable")
  defp failure_label("attempts_exhausted"), do: gettext("Se agotaron los reintentos")
  defp failure_label(_), do: gettext("No se pudo identificar")
end

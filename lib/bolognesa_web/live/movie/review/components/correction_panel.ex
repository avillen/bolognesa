defmodule BolognesaWeb.Movie.Review.Components.CorrectionPanel do
  @moduledoc false
  use BolognesaWeb, :html

  attr :form, :any, required: true
  attr :selected_file_id, :any, required: true
  attr :searching?, :boolean, required: true
  attr :saving?, :boolean, required: true
  attr :candidates, :list, required: true

  def panel(assigns) do
    ~H"""
    <div class="rounded-2xl border border-border bg-surface p-5 sm:p-7">
      <h2 class="text-xl font-semibold text-ink">{gettext("Corrección manual")}</h2>
      <p class="mt-2 text-sm text-muted">
        {if @selected_file_id,
          do: gettext("Archivo seleccionado: %{value0}", value0: @selected_file_id),
          else: gettext("Selecciona un archivo de la lista.")}
      </p>
      <.form
        for={@form}
        id="correction-form"
        phx-change="search"
        phx-submit="search"
        class="mt-5 space-y-4"
      >
        <.input
          field={@form[:query]}
          phx-debounce="300"
          id="correction-query"
          type="search"
          label={gettext("Buscar en TMDb")}
          class="w-full rounded-xl border border-border-strong bg-raised px-4 py-3 text-ink outline-none focus:border-accent"
        />
        <button
          id="correction-search"
          type="submit"
          disabled={is_nil(@selected_file_id) || @searching?}
          class="min-h-11 w-full rounded-xl border border-accent/50 px-4 font-semibold text-accent-soft transition hover:bg-accent/10 disabled:opacity-50"
        >{if @searching?, do: gettext("Buscando…"), else: gettext("Buscar")}</button>
      </.form>
      <div id="correction-candidates" class="mt-5 space-y-2">
        <button
          :for={candidate <- @candidates}
          id={"candidate-#{candidate.provider_id}"}
          type="button"
          phx-click="choose_candidate"
          phx-value-tmdb_id={candidate.provider_id}
          class="min-h-11 w-full rounded-xl border border-border-strong p-3 text-left text-sm text-ink transition hover:border-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >{candidate.title} {candidate.year}</button>
      </div>
      <.form for={@form} id="correction-choice-form" phx-submit="correct" class="mt-5 space-y-3">
        <.input
          field={@form[:tmdb_id]}
          id="correction-tmdb-id"
          type="number"
          label={gettext("ID de TMDb")}
          min="1"
          class="w-full rounded-xl border border-border-strong bg-raised px-4 py-3 text-ink outline-none focus:border-accent"
        />
        <button
          id="correction-submit"
          type="submit"
          disabled={is_nil(@selected_file_id) || @saving?}
          phx-disable-with={gettext("Guardando…")}
          class="min-h-11 w-full rounded-xl bg-accent px-4 font-semibold text-canvas transition hover:bg-accent-hover disabled:opacity-50"
        >{gettext("Confirmar película")}</button>
      </.form>
      <button
        id="correction-unidentified"
        type="button"
        phx-click="unidentified"
        disabled={is_nil(@selected_file_id) || @saving?}
        class="mt-3 min-h-11 w-full rounded-xl border border-border-strong px-4 text-sm text-ink transition hover:border-border-strong disabled:opacity-50"
      >{gettext("Dejar sin identificar")}</button>
    </div>
    """
  end
end

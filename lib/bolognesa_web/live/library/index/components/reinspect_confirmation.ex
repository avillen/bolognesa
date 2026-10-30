defmodule BolognesaWeb.Library.Index.Components.ReinspectConfirmation do
  @moduledoc false
  use BolognesaWeb, :html

  attr :target, :map, required: true

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div
      id="library-reinspect-overlay"
      class="library-create-overlay"
      phx-remove={JS.focus(to: "#library-details-#{@target.id} > summary")}
    >
      <.focus_wrap
        id={"library-reinspect-confirm-#{@target.id}"}
        role="dialog"
        aria-modal="true"
        aria-label={gettext("Confirmar nuevo análisis")}
        class="library-create-panel"
        phx-window-keydown="cancel_reinspect"
        phx-key="Escape"
        phx-mounted={JS.focus(to: "#library-reinspect-cancel-button-#{@target.id}")}
      >
        <p class="mb-2 font-semibold text-ink">{@target.name}</p>
        <p class="text-sm leading-6 text-accent-soft">
          {gettext(
            "Se volverán a leer los archivos de esta biblioteca. El análisis puede tardar y utilizar recursos del servidor."
          )}
        </p>
        <div class="mt-4 flex flex-wrap gap-2">
          <button
            id={"library-reinspect-confirm-button-#{@target.id}"}
            type="button"
            phx-click="confirm_reinspect"
            phx-value-library_id={@target.id}
            class="min-h-11 rounded-xl bg-accent px-4 py-2 font-semibold text-canvas transition hover:bg-accent-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >{gettext("Confirmar")}</button>
          <button
            id={"library-reinspect-cancel-button-#{@target.id}"}
            type="button"
            phx-click="cancel_reinspect"
            class="min-h-11 rounded-xl border border-border-strong px-4 py-2 text-ink transition hover:border-border-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >{gettext("Cancelar")}</button>
        </div>
      </.focus_wrap>
    </div>
    """
  end
end

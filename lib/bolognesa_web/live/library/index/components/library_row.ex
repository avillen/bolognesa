defmodule BolognesaWeb.Library.Index.Components.LibraryRow do
  @moduledoc false
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :library, BolognesaWeb.Library.Index.State.Library, required: true

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <article
      id={@id}
      data-library-name={@library.name}
      data-content-type={@library.content_type}
      class="library-row library-columns"
      aria-labelledby={"library-name-#{@library.id}"}
    >
      <div class="library-identity">
        <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-accent/10 text-accent-soft">
          <.icon
            name={
              case @library.content_type do
                :movie -> "hero-film"
                :series -> "hero-tv"
                :music -> "hero-musical-note"
              end
            }
            class="size-5"
          />
        </span>
        <div class="min-w-0">
          <h3
            id={"library-name-#{@library.id}"}
            class="break-words text-sm font-semibold text-ink"
          >
            {@library.name}
          </h3><p class="mt-1 text-xs text-muted">{@library.content_type_label}</p>
        </div>
      </div>
      <p class="library-path truncate font-mono text-xs text-muted" title={@library.path}>
        {@library.path}
      </p>
      <p id={"library-scan-count-#{@library.id}"} class="library-files text-sm text-ink">
        {ngettext("%{count} archivo", "%{count} archivos", @library.files_discovered)}
      </p>
      <div class="library-status" role="status">
        <p
          id={"library-scan-state-#{@library.id}"}
          data-state={@library.state}
          class={[
            "flex items-center gap-2 text-xs font-medium",
            @library.state == :completed && "text-emerald-200",
            @library.active? && "text-amber-200",
            @library.state == :failed && "text-red-200",
            @library.state == :not_scanned && "text-muted"
          ]}
        >
          <.icon
            :if={@library.active?}
            name="hero-arrow-path"
            class="size-4 shrink-0 motion-safe:animate-spin"
          />{@library.state_label}
        </p>
        <p
          :if={@library.inspection_active? || @library.inspection_counts.failed > 0}
          class="mt-1 text-xs text-muted"
        >
          {ngettext(
            "%{count} en curso",
            "%{count} en curso",
            @library.inspection_counts.pending + @library.inspection_counts.running
          )} · {ngettext(
            "%{count} con error",
            "%{count} con error",
            @library.inspection_counts.failed
          )}
        </p>
      </div>
      <div class="library-actions">
        <button
          id={"library-scan-#{@library.id}"}
          type="button"
          phx-click="scan"
          phx-value-library_id={@library.id}
          disabled={@library.active?}
          phx-disable-with={gettext("Solicitando…")}
          class="library-secondary"
        >
          <.icon name="hero-arrow-path" class="size-4" />{@library.button_label}
        </button>
      </div>
      <details
        id={"library-details-#{@library.id}"}
        phx-mounted={JS.ignore_attributes("open")}
        class="library-details"
      >
        <summary class="min-h-11 cursor-pointer py-3 text-xs text-muted focus-visible:outline-2 focus-visible:outline-accent">
          {gettext("Detalles del escaneo")}
        </summary>
        <div class="library-scan-details">
          <div class="min-w-0 flex-1 space-y-3">
            <div
              :if={@library.last_completed_at || @library.state != :not_scanned}
              class="library-scan-meta"
            >
              <p
                :if={@library.last_completed_at}
                id={"library-scan-completed-#{@library.id}"}
                class="text-xs text-muted"
              >
                {gettext("Último escaneo completo:")} {@library.last_completed_at}
              </p>
              <p :if={@library.state != :not_scanned} class="text-xs text-muted">
                {gettext("Intento %{attempt}", attempt: @library.attempt)}
              </p>
            </div>
            <p
              id={"library-inspection-counts-#{@library.id}"}
              role="status"
              data-pending={@library.inspection_counts.pending}
              data-running={@library.inspection_counts.running}
              data-succeeded={@library.inspection_counts.succeeded}
              data-failed={@library.inspection_counts.failed}
              class="text-sm leading-6 text-ink"
            >
              {@library.inspection_summary}
            </p>
            <ul
              :if={@library.inspection_failure_reasons != []}
              id={"library-inspection-failures-#{@library.id}"}
              class="space-y-1 border-l-2 border-red-300/40 pl-3 text-xs leading-5 text-red-200"
            >
              <li
                :for={failure <- @library.inspection_failure_reasons}
                id={"library-inspection-failure-#{@library.id}-#{failure.reason}"}
              >
                {failure.count} · {failure.label}
              </li>
            </ul>
            <p
              :if={@library.inspection_counts.failed > 0}
              id={"library-inspection-help-#{@library.id}"}
              class="max-w-prose text-xs leading-5 text-muted"
            >
              {gettext(
                "El análisis técnico no terminó para esos archivos. Esto no confirma un problema de reproducción."
              )}
            </p>
          </div>
          <button
            id={"library-reinspect-#{@library.id}"}
            type="button"
            phx-click="prepare_reinspect"
            phx-value-library_id={@library.id}
            disabled={@library.active?}
            class="library-secondary"
          >{gettext("Reanalizar")}</button>
        </div>
      </details>
      <div
        :if={@library.error}
        id={"library-scan-error-#{@library.id}"}
        role="alert"
        class="mt-4 rounded-lg border border-red-300/20 bg-red-300/10 p-3 text-sm text-red-200"
      >
        <p class="flex items-center gap-2 font-semibold">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
          {gettext("Inventario incompleto")}
        </p>
        <p class="mt-2">{@library.error}</p>
        <p class="mt-2 text-xs leading-5">
          {ngettext(
            "%{count} archivo registrado antes del fallo. El escaneo no ha terminado de recorrer la carpeta.",
            "%{count} archivos registrados antes del fallo. El escaneo no ha terminado de recorrer la carpeta.",
            @library.files_discovered
          )}
        </p>
        <p :if={@library.inspection_active?} class="mt-2 text-xs leading-5">
          {gettext(
            "El análisis de los archivos ya registrados continúa. Puedes salir de esta pantalla mientras termina."
          )}
        </p>
      </div>
    </article>
    """
  end
end

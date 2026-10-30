defmodule BolognesaWeb.Library.Index.Components.LibraryForm do
  @moduledoc false
  use BolognesaWeb, :html

  attr :form, Phoenix.HTML.Form, required: true
  attr :error, :string, default: nil

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div
      id="library-create-overlay"
      class="library-create-overlay"
      phx-remove={JS.focus(to: "#library-add")}
    >
      <.focus_wrap
        id="library-create-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="library-create-title"
        class="library-create-panel"
        phx-window-keydown="close_library_form"
        phx-key="Escape"
        phx-mounted={JS.focus(to: "#library-name")}
      >
        <div class="flex items-center justify-between gap-4">
          <h2 id="library-create-title" class="text-xl font-semibold text-ink">
            {gettext("Añadir biblioteca")}
          </h2>
          <button
            id="library-create-close"
            type="button"
            phx-click="close_library_form"
            aria-label={gettext("Cerrar")}
            class="library-secondary"
          ><.icon name="hero-x-mark" class="size-5" /></button>
        </div>
        <p class="mt-2 text-sm leading-6 text-muted">
          {gettext("Usa la ruta visible para Bolognesa dentro del servidor.")}
        </p>
        <p class="mt-2 text-sm leading-6 text-muted">
          <a
            id="library-deployment-help"
            href="https://github.com/avillen/bolognesa/blob/main/deploy/compose/README.md#networking-persistence-and-libraries"
            class="text-accent underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >{gettext("Docker Compose: consulta la guía de montajes y carpetas permitidas.")}</a>
        </p>
        <p
          :if={@error}
          id="library-error"
          role="alert"
          class="mt-5 rounded-xl border border-red-400/30 bg-red-400/10 p-4 text-sm text-red-200"
        >
          {@error}
        </p>
        <.form
          for={@form}
          id="library-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-6 space-y-5"
        >
          <.input
            field={@form[:name]}
            id="library-name"
            type="text"
            label={gettext("Nombre")}
            required
            class="w-full rounded-xl border border-border-strong bg-raised px-4 py-3 text-ink outline-none transition focus:border-accent focus:ring-2 focus:ring-accent/30"
          />
          <.input
            field={@form[:content_type]}
            id="library-content-type"
            type="select"
            label={gettext("Contenido")}
            options={[
              {gettext("Películas"), :movie},
              {gettext("Series"), :series},
              {gettext("Música"), :music}
            ]}
            required
          />
          <.input
            field={@form[:path]}
            id="library-path"
            type="text"
            label={gettext("Carpeta de origen")}
            placeholder="/media/movies"
            required
            class="w-full rounded-xl border border-border-strong bg-raised px-4 py-3 text-ink outline-none transition focus:border-accent focus:ring-2 focus:ring-accent/30"
          />
          <button
            id="library-create-cancel"
            type="button"
            phx-click="close_library_form"
            class="library-secondary w-full"
          >{gettext("Cancelar")}</button>
          <button
            id="library-submit"
            type="submit"
            phx-disable-with={gettext("Guardando…")}
            class="min-h-12 w-full rounded-xl bg-accent px-5 py-3 font-semibold text-canvas transition hover:bg-accent-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >{gettext("Guardar biblioteca")}</button>
        </.form>
      </.focus_wrap>
    </div>
    """
  end
end

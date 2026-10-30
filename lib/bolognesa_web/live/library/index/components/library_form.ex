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
            class="library-create-close"
          ><.icon name="hero-x-mark" class="size-5" /></button>
        </div>
        <p class="mt-2 text-sm leading-6 text-muted">
          {gettext("Usa la ruta visible para Bolognesa dentro del servidor.")}
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
          class="library-create-form mt-6"
        >
          <.input
            field={@form[:name]}
            id="library-name"
            type="text"
            label={gettext("Nombre")}
            required
            class="library-form-control"
            error_class="library-form-control-error"
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
            class="library-form-control library-form-select"
            error_class="library-form-control-error"
          />
          <div class="library-source-field">
            <.input
              field={@form[:path]}
              id="library-path"
              type="text"
              label={gettext("Carpeta de origen")}
              placeholder="/media/movies"
              aria-describedby="library-deployment-help"
              required
              class="library-form-control"
              error_class="library-form-control-error"
            />
            <a
              id="library-deployment-help"
              href="https://github.com/avillen/bolognesa/blob/main/deploy/compose/README.md#networking-persistence-and-libraries"
              target="_blank"
              rel="noopener noreferrer"
              class="library-deployment-help"
            >{gettext("Ayuda con las carpetas del servidor (abre en otra pestaña)")}</a>
          </div>
          <div class="library-form-actions">
            <button
              id="library-create-cancel"
              type="button"
              phx-click="close_library_form"
              class="library-secondary"
            >{gettext("Cancelar")}</button>
            <button
              id="library-submit"
              type="submit"
              phx-disable-with={gettext("Guardando…")}
              class="library-primary"
            >{gettext("Guardar biblioteca")}</button>
          </div>
        </.form>
      </.focus_wrap>
    </div>
    """
  end
end

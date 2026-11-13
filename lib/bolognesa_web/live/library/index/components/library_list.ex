defmodule BolognesaWeb.Library.Index.Components.LibraryList do
  @moduledoc false
  use BolognesaWeb, :html

  alias BolognesaWeb.Library.Index.Components.LibraryRow

  attr :libraries, :any, required: true
  attr :load_error, :string, default: nil

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <section class="library-section" aria-labelledby="registered-libraries-title">
      <h2
        id="registered-libraries-title"
        class="px-1 pb-4 text-base font-semibold text-ink md:px-5 md:pt-5"
      >
        {gettext("Bibliotecas registradas")}
      </h2>
      <div class="library-columns library-list-heading" aria-hidden="true">
        <span>{gettext("Biblioteca")}</span><span>{gettext("Carpeta de origen")}</span><span>{gettext(
          "Archivos"
        )}</span><span>{gettext("Estado")}</span><span class="text-right">{gettext("Acciones")}</span>
      </div>
      <div id="library-list" phx-update="stream" class="library-list">
        <div
          :if={is_nil(@load_error)}
          id="libraries-empty"
          class="hidden rounded-xl border border-dashed border-border p-6 text-sm text-muted only:block"
        >
          <p>{gettext("Todavía no hay bibliotecas.")}</p>
          <button type="button" phx-click="open_library_form" class="library-secondary mt-4">{gettext(
            "Añadir biblioteca"
          )}</button>
        </div>
        <LibraryRow.render :for={{id, library} <- @libraries} id={id} library={library} />
      </div>
    </section>
    """
  end
end

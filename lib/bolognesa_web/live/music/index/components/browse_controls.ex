defmodule BolognesaWeb.Music.Index.Components.BrowseControls do
  @moduledoc "Navigation, search, feedback and pagination for music browsing."
  use BolognesaWeb, :html

  attr :browse_kind, :atom, required: true
  attr :library_params, :map, required: true
  attr :artist_id, :integer, default: nil

  @spec navigation(map()) :: Phoenix.LiveView.Rendered.t()
  def navigation(assigns) do
    ~H"""
    <nav aria-label={gettext("Explorar música")} class="music-tabs">
      <.link
        id="music-home-link"
        patch={~p"/music?#{@library_params}"}
        aria-current={@browse_kind == :home && "page"}
        class="music-tab"
      >{gettext("Inicio")}</.link>
      <.link
        id="music-artists-link"
        patch={~p"/music?#{Map.put(@library_params, :view, :artists)}"}
        aria-current={@browse_kind == :artists && "page"}
        class="music-tab"
      >{gettext("Artistas")}</.link>
      <.link
        id="music-albums-link"
        patch={~p"/music?#{Map.put(@library_params, :view, :albums)}"}
        aria-current={@browse_kind == :albums && !@artist_id && "page"}
        class="music-tab"
      >{gettext("Álbumes")}</.link>
      <.link
        id="music-songs-link"
        patch={~p"/music?#{Map.put(@library_params, :view, :tracks)}"}
        aria-current={@browse_kind == :tracks && "page"}
        class="music-tab"
      >{gettext("Canciones")}</.link>
    </nav>
    """
  end

  attr :form, :any, required: true

  @spec search(map()) :: Phoenix.LiveView.Rendered.t()
  def search(assigns) do
    ~H"""
    <.form
      for={@form}
      id="music-search"
      phx-change="search"
      phx-submit="search"
      class="music-search"
    >
      <.input
        field={@form[:query]}
        phx-debounce="300"
        type="search"
        label={gettext("Buscar canciones, artistas o álbumes")}
        placeholder={gettext("Buscar música")}
      />
      <button
        type="submit"
        class="min-h-11 rounded-lg bg-accent px-4 py-2 font-semibold text-canvas hover:bg-accent-hover disabled:opacity-50"
      >{gettext("Buscar")}</button>
    </.form>
    """
  end

  attr :loading?, :boolean, required: true
  attr :error, :any, default: nil
  attr :browse_kind, :atom, required: true
  attr :total, :integer, required: true

  @spec feedback(map()) :: Phoenix.LiveView.Rendered.t()
  def feedback(assigns) do
    ~H"""
    <p :if={@loading?} id="music-loading" role="status" class="music-feedback">
      {gettext("Cargando música…")}
    </p>
    <div
      :if={@error}
      id="music-read-error"
      role="alert"
      class="music-feedback music-feedback-error"
    >
      <p>{@error}</p><button
        type="button"
        phx-click="refresh"
        class="min-h-11 rounded-lg border border-border-strong px-4 py-2 text-ink hover:bg-raised disabled:opacity-50"
      >{gettext("Reintentar")}</button>
    </div>
    <p
      :if={@browse_kind != :home && !@loading? && !@error && @total == 0}
      id="music-empty"
      class="music-feedback"
    >
      {gettext("No hay resultados. Prueba otra búsqueda o escanea tu biblioteca de música.")}
    </p>
    """
  end

  attr :total, :integer, required: true
  attr :page_size, :integer, required: true
  attr :page, :integer, required: true
  attr :browse_params, :map, required: true
  attr :query, :string, required: true

  @spec pagination(map()) :: Phoenix.LiveView.Rendered.t()
  def pagination(assigns) do
    ~H"""
    <nav
      :if={@total > @page_size}
      aria-label={gettext("Paginación de música")}
      class="flex items-center justify-between gap-3"
    >
      <.link
        :if={@page > 1}
        patch={~p"/music?#{Map.merge(@browse_params, %{query: @query, page: @page - 1})}"}
        class="min-h-11 rounded-lg border border-border-strong px-4 py-2 text-ink hover:bg-raised disabled:opacity-50"
      >{gettext("Anterior")}</.link>
      <span>{gettext("Página %{page}", page: @page)}</span>
      <.link
        :if={@page * @page_size < @total}
        patch={~p"/music?#{Map.merge(@browse_params, %{query: @query, page: @page + 1})}"}
        class="min-h-11 rounded-lg border border-border-strong px-4 py-2 text-ink hover:bg-raised disabled:opacity-50"
      >{gettext("Siguiente")}</.link>
    </nav>
    """
  end
end

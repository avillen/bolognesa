defmodule BolognesaWeb.Music.Index.Components.BrowseControls do
  @moduledoc "Navigation, search, feedback and pagination for music browsing."
  use BolognesaWeb, :html

  attr :browse_kind, :atom, required: true
  attr :library_params, :map, required: true
  attr :artist_id, :integer, default: nil

  @spec navigation(map()) :: Phoenix.LiveView.Rendered.t()
  def navigation(assigns) do
    # Links styled as ghost buttons; aria-current, not ARIA tabs, marks the section.
    assigns =
      assign(
        assigns,
        :link_class,
        button_variant(%{variant: "ghost"}) <>
          " h-10 flex-none px-3 text-muted-foreground hover:text-foreground sm:px-4" <>
          " aria-[current=page]:bg-primary/15 aria-[current=page]:text-foreground" <>
          " aria-[current=page]:ring-1 aria-[current=page]:ring-inset aria-[current=page]:ring-primary/30" <>
          " focus-visible:outline-offset-2! motion-reduce:transition-none"
      )

    ~H"""
    <nav
      aria-label={gettext("Explorar música")}
      class="flex max-w-full gap-0.5 overflow-x-auto max-sm:self-start rounded-xl border border-border bg-card p-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
    >
      <.link
        id="music-home-link"
        patch={~p"/music?#{@library_params}"}
        aria-current={@browse_kind == :home && "page"}
        class={@link_class}
      >{gettext("Inicio")}</.link>
      <.link
        id="music-artists-link"
        patch={~p"/music?#{Map.put(@library_params, :view, :artists)}"}
        aria-current={@browse_kind == :artists && "page"}
        class={@link_class}
      >{gettext("Artistas")}</.link>
      <.link
        id="music-albums-link"
        patch={~p"/music?#{Map.put(@library_params, :view, :albums)}"}
        aria-current={@browse_kind == :albums && !@artist_id && "page"}
        class={@link_class}
      >{gettext("Álbumes")}</.link>
      <.link
        id="music-songs-link"
        patch={~p"/music?#{Map.put(@library_params, :view, :tracks)}"}
        aria-current={@browse_kind == :tracks && "page"}
        class={@link_class}
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
      <.icon name="hero-magnifying-glass" class="music-search-icon size-5" />
      <.input
        field={@form[:query]}
        phx-debounce="300"
        type="search"
        class="music-search-input"
        label={gettext("Buscar canciones, artistas o álbumes")}
        placeholder={gettext("Buscar música")}
      />
      <Button.button
        type="submit"
        variant="ghost"
        class="music-search-submit h-10 min-h-10 text-accent-soft"
      >
        {gettext("Buscar")}
      </Button.button>
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
    <Alert.alert
      :if={@error}
      id="music-read-error"
      variant="destructive"
      class="flex flex-wrap items-center justify-between gap-3"
    >
      <Alert.alert_description>
        <p>{@error}</p>
      </Alert.alert_description>
      <Button.button type="button" phx-click="refresh" variant="outline" class="text-foreground">
        {gettext("Reintentar")}
      </Button.button>
    </Alert.alert>
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
      class="music-pagination"
    >
      <.link
        :if={@page > 1}
        patch={~p"/music?#{Map.merge(@browse_params, %{query: @query, page: @page - 1})}"}
        class="music-page-link"
      ><.icon name="hero-chevron-left" class="size-4" />{gettext("Anterior")}</.link>
      <span class="music-page-current">{gettext("Página %{page}", page: @page)}</span>
      <.link
        :if={@page * @page_size < @total}
        patch={~p"/music?#{Map.merge(@browse_params, %{query: @query, page: @page + 1})}"}
        class="music-page-link"
      >{gettext("Siguiente")}<.icon name="hero-chevron-right" class="size-4" /></.link>
    </nav>
    """
  end
end

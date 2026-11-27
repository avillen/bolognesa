defmodule BolognesaWeb.MediaComponents do
  @moduledoc "Presentation shared by movie, series, episode and music screens."
  use BolognesaWeb, :html

  attr :id, :string, required: true
  attr :text, :string, required: true

  @spec synopsis(map()) :: Phoenix.LiveView.Rendered.t()
  def synopsis(assigns) do
    ~H"""
    <details
      id={@id}
      class="media-expandable-synopsis"
      phx-hook="ExpandableSynopsis"
      phx-mounted={JS.ignore_attributes("open")}
    >
      <summary>
        <span class="media-expandable-synopsis-text">{@text}</span>
        <span class="media-read-more">{gettext("Leer más")}</span>
        <span class="media-read-less">{gettext("Leer menos")}</span>
      </summary>
    </details>
    """
  end

  attr :id, :string, required: true

  attr :watched_at, :any,
    default: nil,
    doc: "DateTime of the latest viewing, or nil when unwatched"

  attr :class, :string, default: nil

  @spec watched_state(map()) :: Phoenix.LiveView.Rendered.t()
  def watched_state(assigns) do
    ~H"""
    <p :if={@watched_at} id={@id} class={["text-xs text-muted", @class]}>
      {gettext("Visto")} ·
      <time datetime={Date.to_iso8601(@watched_at)}>{Calendar.strftime(@watched_at, "%d/%m/%Y")}</time>
    </p>
    """
  end

  attr :id, :string, required: true
  attr :watched?, :boolean, required: true

  @spec watched_action(map()) :: Phoenix.LiveView.Rendered.t()
  def watched_action(assigns) do
    ~H"""
    <Button.button
      id={@id}
      type="button"
      phx-click={if @watched?, do: "unmark_watched", else: "mark_watched"}
      variant="outline"
      class="mt-4"
    >
      <.icon name={if @watched?, do: "hero-eye-slash", else: "hero-eye"} class="size-4" />
      {if @watched?, do: gettext("Marcar como no visto"), else: gettext("Marcar como visto")}
    </Button.button>
    """
  end

  attr :title, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :search_id, :string, required: true
  attr :search_label, :string, required: true
  attr :options_id, :string, required: true
  slot :inner_block, required: true, doc: "the links inside the library options menu"

  @spec catalog_header(map()) :: Phoenix.LiveView.Rendered.t()
  def catalog_header(assigns) do
    ~H"""
    <header class="media-index-heading">
      <h1 class="media-index-title">{@title}</h1>
      <.form
        for={@form}
        id={@search_id}
        phx-change="search"
        phx-submit="search"
        class="media-search-form"
      >
        <div class="media-search-field">
          <.icon name="hero-magnifying-glass" class="size-5 text-muted" />
          <.input
            field={@form[:query]}
            phx-debounce="300"
            type="search"
            label={@search_label}
            placeholder={gettext("Buscar por título…")}
            class="media-search-input"
          />
        </div>
        <Button.button
          type="submit"
          variant="ghost"
          class="px-3 text-muted-foreground"
          aria-label={@search_label}
        >
          <.icon name="hero-arrow-turn-down-left" class="size-5 sm:hidden" />
          <span class="hidden sm:inline">{gettext("Buscar")}</span>
        </Button.button>
      </.form>
      <details id={@options_id} class="media-library-options">
        <summary
          aria-label={gettext("Opciones de biblioteca")}
          class={
            button_variant(
              %{variant: "subtle", size: "icon"},
              "list-none in-open:bg-secondary in-open:text-secondary-foreground [&::-webkit-details-marker]:hidden"
            )
          }
        >
          <.icon name="hero-ellipsis-horizontal" class="size-5" />
        </summary>
        <div class="media-options-menu">
          {render_slot(@inner_block)}
        </div>
      </details>
    </header>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :navigate, :string, required: true, doc: "path of the title's page"
  attr :art, :string, default: nil, doc: "TMDB backdrop or poster path"
  attr :icon, :string, required: true, doc: "placeholder shown without art"
  attr :overview, :string, default: nil, doc: "synopsis shown only on the lead tile"
  attr :lead?, :boolean, default: false

  slot :action,
    required: true,
    doc: "the tile action; receives the class that fits the tile size"

  @doc "Landscape tile of the recently watched marquee; the first one leads with its synopsis."
  @spec shelf_tile(map()) :: Phoenix.LiveView.Rendered.t()
  def shelf_tile(assigns) do
    ~H"""
    <article id={@id} class={["media-shelf-tile", @lead? && "is-lead"]}>
      <div class="media-shelf-art" aria-hidden="true">
        <.icon name={@icon} class="size-8" />
        <img
          :if={@art}
          id={"#{@id}-art"}
          phx-hook="ImageFallback"
          phx-update="ignore"
          src={"https://image.tmdb.org/t/p/#{if @lead?, do: "w1280", else: "w780"}#{@art}"}
          alt=""
          loading="lazy"
        />
      </div>
      <div class="media-shelf-copy">
        <h3><.link navigate={@navigate}>{@title}</.link></h3>
        <p :if={@lead? && @overview} class="media-shelf-overview">{@overview}</p>
        {render_slot(
          @action,
          if(@lead?, do: button_variant(%{}, "mt-5"), else: "media-shelf-action")
        )}
      </div>
    </article>
    """
  end

  attr :id, :string, default: nil
  attr :retry, :string, default: nil, doc: "the event the retry button pushes"
  attr :patch, :string, default: nil, doc: "path to patch to instead of `retry`"
  slot :inner_block, required: true

  @spec retry_alert(map()) :: Phoenix.LiveView.Rendered.t()
  def retry_alert(assigns) do
    ~H"""
    <Alert.alert
      id={@id}
      variant="destructive"
      class="flex flex-wrap items-center justify-between gap-3"
    >
      {render_slot(@inner_block)}
      <.link :if={@patch} patch={@patch} class={button_variant(%{variant: "outline"})}>
        {gettext("Reintentar")}
      </.link>
      <Button.button :if={!@patch} type="button" phx-click={@retry} variant="outline">
        {gettext("Reintentar")}
      </Button.button>
    </Alert.alert>
    """
  end

  attr :id, :string,
    required: true,
    doc: "prefix for the nav (`<id>-pagination`) and link (`<id>-previous`, `<id>-next`) ids"

  attr :label, :string, required: true, doc: "accessible name of the nav"
  attr :page, :integer, required: true
  attr :page_size, :integer, required: true
  attr :total, :integer, required: true
  attr :path, :any, required: true, doc: "function from a page number to its patch path"

  @spec pagination(map()) :: Phoenix.LiveView.Rendered.t()
  def pagination(assigns) do
    ~H"""
    <nav
      :if={@total > @page_size}
      id={"#{@id}-pagination"}
      aria-label={@label}
      class="flex flex-wrap items-center justify-center gap-3"
    >
      <.link
        :if={@page > 1}
        id={"#{@id}-previous"}
        patch={@path.(@page - 1)}
        class={button_variant(%{variant: "outline", shape: "pill"})}
      ><.icon name="hero-chevron-left" class="size-4" />{gettext("Anterior")}</.link>
      <span class="text-sm text-muted tabular-nums">{gettext("Página %{page}", page: @page)}</span>
      <.link
        :if={@page * @page_size < @total}
        id={"#{@id}-next"}
        patch={@path.(@page + 1)}
        class={button_variant(%{variant: "outline", shape: "pill"})}
      >{gettext("Siguiente")}<.icon name="hero-chevron-right" class="size-4" /></.link>
    </nav>
    """
  end
end

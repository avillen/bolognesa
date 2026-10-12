defmodule BolognesaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BolognesaWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active_section, :atom, default: nil

  attr :navigation_libraries, :list, default: []
  attr :navigation_error, :string, default: nil
  attr :active_library_id, :integer, default: nil

  slot :inner_block, required: true

  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    <div class="app-shell">
      <header class="app-sidebar">
        <.link navigate={~p"/"} class="app-brand">
          <img src={~p"/images/bolognesa-cat.svg"} width="36" height="36" alt="" />
          <span>boloñesa</span>
        </.link>
        <nav aria-label={gettext("Navegación principal")} class="app-navigation">
          <div class="app-nav-primary">
            <.link
              navigate={~p"/"}
              class={["app-nav-link", @active_section == :home && "is-active"]}
              aria-current={@active_section == :home && "page"}
            >
              <.icon name="hero-home" class="size-5" /> <span>{gettext("Inicio")}</span>
            </.link>
            <.link
              :for={library <- @navigation_libraries}
              id={"nav-library-#{library.id}"}
              navigate={library_path(library)}
              class={["app-nav-link", @active_library_id == library.id && "is-active"]}
              aria-current={@active_library_id == library.id && "page"}
            >
              <.icon
                name={if library.content_type == :movie, do: "hero-film", else: "hero-tv"}
                class="size-5 shrink-0"
              />
              <span class="min-w-0 break-words">{library.name}</span>
            </.link>
            <p
              :if={@navigation_error}
              id="navigation-error"
              role="alert"
              class="px-3 text-sm text-muted"
            >
              {@navigation_error}
            </p>
          </div>
          <div class="app-nav-secondary">
            <.link
              navigate={~p"/libraries"}
              class={["app-nav-link", @active_section == :libraries && "is-active"]}
              aria-current={@active_section == :libraries && "page"}
            >
              <.icon name="hero-folder" class="size-5" /> <span>{gettext("Bibliotecas")}</span>
            </.link>
            <.link
              navigate={~p"/settings"}
              id="nav-settings"
              class={["app-nav-link", @active_section == :settings && "is-active"]}
              aria-current={@active_section == :settings && "page"}
            >
              <.icon name="hero-cog-6-tooth" class="size-5" /> <span>{gettext("Ajustes")}</span>
            </.link>
            <.link
              navigate={~p"/about"}
              class={["app-nav-link", @active_section == :about && "is-active"]}
              aria-current={@active_section == :about && "page"}
            >
              <.icon name="hero-information-circle" class="size-5" />
              <span>{gettext("Acerca de")}</span>
            </.link>
          </div>
        </nav>
        <p class="app-sidebar-note">{gettext("Tu cine, en casa.")}</p>
      </header>
      <main id="app-content" class="app-content">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp library_path(%{content_type: :movie, id: id}), do: ~p"/movies?#{%{library_id: id}}"
  defp library_path(%{content_type: :series, id: id}), do: ~p"/series?#{%{library_id: id}}"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  @spec flash_group(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end

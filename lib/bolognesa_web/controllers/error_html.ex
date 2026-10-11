defmodule BolognesaWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use BolognesaWeb, :html

  # If you want to customize your error pages,
  # uncomment the embed_templates/1 call below
  # and add pages to the error directory:
  #
  #   * lib/bolognesa_web/controllers/error_html/404.html.heex
  #   * lib/bolognesa_web/controllers/error_html/500.html.heex
  #
  # embed_templates "error_html/*"

  # The default is to render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Not Found".
  @spec render(String.t(), map()) :: String.t()
  def render(template, assigns) do
    Gettext.with_locale(BolognesaWeb.Gettext, locale(assigns), fn -> message(template) end)
  end

  defp message("404.html"), do: gettext("Página no encontrada")
  defp message("500.html"), do: gettext("Error interno del servidor")
  defp message(template), do: Phoenix.Controller.status_message_from_template(template)

  defp locale(%{conn: conn}) do
    conn.assigns[:locale] ||
      BolognesaWeb.Locale.negotiate(List.first(Plug.Conn.get_req_header(conn, "accept-language")))
  end

  defp locale(_), do: Gettext.get_locale(BolognesaWeb.Gettext)
end

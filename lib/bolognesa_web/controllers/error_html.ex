defmodule BolognesaWeb.ErrorHTML do
  alias BolognesaWeb.Locale
  alias Phoenix.Controller

  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use BolognesaWeb, :html

  @spec render(String.t(), map()) :: String.t()
  def render(template, assigns) do
    Gettext.with_locale(BolognesaWeb.Gettext, locale(assigns), fn -> message(template) end)
  end

  defp message("404.html"), do: gettext("Página no encontrada")
  defp message("500.html"), do: gettext("Error interno del servidor")
  defp message(template), do: Controller.status_message_from_template(template)

  defp locale(%{conn: conn}) do
    conn.assigns[:locale] || Locale.browser(conn)
  end

  defp locale(_), do: Gettext.get_locale(BolognesaWeb.Gettext)
end

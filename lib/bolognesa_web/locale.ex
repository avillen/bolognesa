defmodule BolognesaWeb.Locale do
  @moduledoc "Resolve and install the interface language for each request and LiveView process."
  import Plug.Conn
  alias Bolognesa.Accounts
  alias BolognesaWeb.Gettext, as: Backend
  @supported ["es", "en"]

  @spec negotiate(String.t() | nil) :: String.t()
  def negotiate(header) do
    ranges = parse_header(header || "")
    excluded = for {language, quality} <- ranges, quality == 0.0, do: language

    ranges
    |> Enum.reject(fn {language, quality} -> quality == 0.0 or language in excluded end)
    |> Enum.sort_by(fn {_language, quality} -> -quality end)
    |> Enum.find_value("es", fn {language, _quality} -> available(language, excluded) end)
  end

  defp parse_header(header) do
    header |> String.split(",") |> Enum.flat_map(&parse_range/1)
  end

  defp parse_range(range) do
    case Regex.run(
           ~r/^\s*([a-z]{2}(?:-[a-z0-9]+)*|\*)\s*(?:;\s*q=(0(?:\.[0-9]{1,3})?|1(?:\.0{1,3})?))?\s*$/i,
           range
         ) do
      [_, language] -> [{base(language), 1.0}]
      [_, language, quality] -> [{base(language), quality(quality)}]
      _ -> []
    end
  end

  defp base(language), do: language |> String.downcase() |> String.split("-") |> hd()
  defp quality(value), do: value |> Float.parse() |> elem(0)
  defp available("*", excluded), do: Enum.find(@supported, &(&1 not in excluded))
  defp available(language, _excluded) when language in @supported, do: language
  defp available(_, _), do: nil

  @spec fetch_browser_locale(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_browser_locale(conn, _opts) do
    locale = negotiate(List.first(get_req_header(conn, "accept-language")))
    Gettext.put_locale(Backend, locale)
    conn |> put_session(:browser_locale, locale) |> assign(:locale, locale)
  end

  @spec apply_user_locale(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def apply_user_locale(conn, _opts) do
    locale = effective(conn.assigns[:current_scope], conn.assigns.locale)
    Gettext.put_locale(Backend, locale)
    assign(conn, :locale, locale)
  end

  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    browser =
      if session["browser_locale"] in @supported, do: session["browser_locale"], else: "es"

    scope = Map.get(socket.assigns, :current_scope) || session_scope(session)
    locale = effective(scope, browser)
    Gettext.put_locale(Backend, locale)
    {:cont, Phoenix.Component.assign(socket, locale: locale, browser_locale: browser)}
  end

  defp session_scope(session) do
    case Accounts.fetch_actor(session["user_token"]) do
      {:ok, actor} -> %{actor: actor}
      _ -> nil
    end
  end

  defp effective(%{actor: %{locale: locale}}, _) when locale in @supported, do: locale
  defp effective(_, browser), do: browser
end

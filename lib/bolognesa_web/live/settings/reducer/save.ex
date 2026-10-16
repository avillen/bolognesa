defmodule BolognesaWeb.Settings.Reducer.Save do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]
  use Gettext, backend: BolognesaWeb.Gettext
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Accounts.Domain.ValueObjects.Locale
  alias BolognesaWeb.Settings.Forms.Preferences

  @type operation :: (Actor.t(), Locale.t() ->
                        {:ok, Actor.t()} | {:error, :forbidden | :invalid_locale | :unavailable})
  @spec call(Phoenix.LiveView.Socket.t(), map(), operation()) :: Phoenix.LiveView.Socket.t()
  def call(socket, params, operation \\ &Accounts.update_locale/2) do
    changeset = Preferences.changeset(socket.assigns.current_scope.actor.locale, params)

    case Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, %{locale: locale}} -> save(socket, locale, changeset, operation)
      {:error, changeset} -> assign(socket, :form, to_form(changeset, as: :preferences))
    end
  end

  defp save(socket, value, changeset, operation) do
    locale = if value == "", do: nil, else: value

    case operation.(socket.assigns.current_scope.actor, locale) do
      {:ok, actor} ->
        reload(socket, actor)

      {:error, _} ->
        socket
        |> assign(:form, to_form(changeset, as: :preferences))
        |> put_flash(:error, gettext("No se ha podido guardar el idioma. Vuelve a intentarlo."))
    end
  end

  defp reload(socket, actor) do
    locale = actor.locale || socket.assigns.browser_locale
    Gettext.put_locale(BolognesaWeb.Gettext, locale)

    socket
    |> assign(:current_scope, %{actor: actor})
    |> assign(:locale, locale)
    |> put_flash(:info, gettext("Idioma guardado."))
    |> redirect(to: "/settings")
  end
end

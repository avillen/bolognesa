defmodule BolognesaWeb.Settings.ReducerTest do
  alias Phoenix.Component
  alias Phoenix.Flash
  use ExUnit.Case, async: true
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias BolognesaWeb.Settings.Reducer.Initialize
  alias BolognesaWeb.Settings.Reducer.Save

  test "failed save preserves selection for retry and never reports success" do
    actor = %AuthenticatedUser{id: 1, name: "Ada", email: "ada@example.com", role: :admin}

    socket =
      %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}},
        private: %{live_temp: %{}}
      }
      |> Component.assign(
        current_scope: %{actor: actor},
        browser_locale: "es",
        locale: "es"
      )

    socket = Initialize.call(socket)
    socket = Save.call(socket, %{"locale" => "en"}, fn _, _ -> {:error, :unavailable} end)
    assert socket.assigns.form[:locale].value == "en"
    assert Flash.get(socket.assigns.flash, :error)
    refute Flash.get(socket.assigns.flash, :info)
    refute socket.redirected

    socket =
      Save.call(socket, %{"locale" => "en"}, fn current, locale ->
        {:ok, %{current | locale: locale}}
      end)

    assert {:redirect, %{to: "/settings"}} = socket.redirected
    assert Flash.get(socket.assigns.flash, :info) == "Language saved."
  end
end

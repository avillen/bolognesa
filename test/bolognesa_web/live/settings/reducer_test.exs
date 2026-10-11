defmodule BolognesaWeb.Settings.ReducerTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias BolognesaWeb.Settings.Reducer

  test "failed save preserves selection for retry and never reports success" do
    actor = %Actor{id: 1, name: "Ada", email: "ada@example.com", role: :admin}

    socket =
      %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}},
        private: %{live_temp: %{}}
      }
      |> Phoenix.Component.assign(
        current_scope: %{actor: actor},
        browser_locale: "es",
        locale: "es"
      )

    socket = Reducer.Initialize.call(socket)
    socket = Reducer.Save.call(socket, %{"locale" => "en"}, fn _, _ -> {:error, :unavailable} end)
    assert socket.assigns.form[:locale].value == "en"
    assert Phoenix.Flash.get(socket.assigns.flash, :error)
    refute Phoenix.Flash.get(socket.assigns.flash, :info)
    refute socket.redirected

    socket =
      Reducer.Save.call(socket, %{"locale" => "en"}, fn current, locale ->
        {:ok, %{current | locale: locale}}
      end)

    assert {:redirect, %{to: "/settings"}} = socket.redirected
    assert Phoenix.Flash.get(socket.assigns.flash, :info) == "Language saved."
  end
end

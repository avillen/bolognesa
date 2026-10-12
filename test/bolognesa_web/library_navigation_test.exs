defmodule BolognesaWeb.LibraryNavigationTest do
  use Bolognesa.DataCase, async: false
  alias BolognesaWeb.LibraryNavigation
  alias Phoenix.LiveView.Lifecycle

  test "a failed library read preserves navigation and explains a scoped redirect" do
    Gettext.put_locale(BolognesaWeb.Gettext, "en")
    library = Bolognesa.SeriesFixtures.library(:movie)

    socket = %Phoenix.LiveView.Socket{
      router: BolognesaWeb.Router,
      endpoint: BolognesaWeb.Endpoint,
      private: %{live_temp: %{}, lifecycle: %Lifecycle{}},
      assigns: %{__changed__: %{}, flash: %{}, current_scope: %{actor: nil}}
    }

    {:cont, socket} = LibraryNavigation.on_mount(:default, %{}, %{}, socket)

    socket =
      Phoenix.Component.assign(socket, :navigation_libraries, [
        %{id: library.id, name: library.name, content_type: :movie}
      ])

    socket = LibraryNavigation.refresh(socket)

    {:halt, socket} =
      Lifecycle.handle_params(
        %{"library_id" => "#{library.id}"},
        "http://localhost/movies",
        socket
      )

    assert socket.assigns.navigation_libraries == [
             %{id: library.id, name: library.name, content_type: :movie}
           ]

    assert {:live, :redirect, %{to: "/libraries"}} = socket.redirected
    assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "Libraries"
  end
end

defmodule BolognesaWeb.LibraryNavigation do
  @moduledoc "Load named library navigation at the authenticated LiveView boundary."
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_navigate: 2, put_flash: 3]
  alias Bolognesa.Libraries

  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:navigation_libraries, [])
      |> assign(:navigation_error, nil)
      |> assign(:active_library_id, nil)
      |> assign(:library_name, nil)
      |> assign(:library_params, %{})
      |> refresh()
      |> attach_hook(:library_navigation, :handle_params, &handle_params/3)

    {:cont, socket}
  end

  @spec refresh(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh(socket) do
    case Libraries.list_libraries(socket.assigns.current_scope.actor) do
      {:ok, libraries} ->
        items = Enum.map(libraries, &Map.take(&1, [:id, :name, :content_type]))
        socket |> assign(:navigation_libraries, items) |> assign(:navigation_error, nil)

      {:error, _} ->
        assign(
          socket,
          :navigation_error,
          gettext("No se pudieron cargar las bibliotecas. Recarga para reintentar.")
        )
    end
  end

  defp handle_params(params, uri, socket) do
    select_library(socket, Map.get(params, "library_id"), URI.parse(uri).path)
  end

  defp select_library(socket, nil, _path) do
    {:cont,
     socket
     |> assign(:active_library_id, nil)
     |> assign(:library_name, nil)
     |> assign(:library_params, %{})}
  end

  defp select_library(%{assigns: %{navigation_error: error}} = socket, _value, _path)
       when is_binary(error) do
    {:halt, socket |> put_flash(:error, error) |> push_navigate(to: "/libraries")}
  end

  defp select_library(socket, value, path) do
    library = find_library(socket.assigns.navigation_libraries, value)
    apply_selection(socket, library, path)
  end

  defp find_library(libraries, value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> Enum.find(libraries, &(&1.id == id))
      _ -> nil
    end
  end

  defp find_library(_libraries, _value), do: nil

  defp apply_selection(socket, nil, _path),
    do: {:halt, push_navigate(socket, to: "/libraries")}

  defp apply_selection(socket, library, path) do
    if matching_type?(library.content_type, path) do
      {:cont,
       socket
       |> assign(:active_library_id, library.id)
       |> assign(:library_name, library.name)
       |> assign(:library_params, %{library_id: library.id})}
    else
      {:halt, push_navigate(socket, to: "/libraries")}
    end
  end

  defp matching_type?(:movie, "/movies" <> _), do: true
  defp matching_type?(:series, "/series" <> _), do: true
  defp matching_type?(:series, "/episodes/" <> _), do: true
  defp matching_type?(_type, _path), do: false
end

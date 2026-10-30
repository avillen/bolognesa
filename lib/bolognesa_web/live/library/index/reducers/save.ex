defmodule BolognesaWeb.Library.Index.Reducers.Save do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [stream_insert: 3]

  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus

  alias BolognesaWeb.Library.Index.Forms.Library
  alias BolognesaWeb.Library.Index.Reducers.CancelScanStatuses
  alias BolognesaWeb.Library.Index.Reducers.FetchScanStatuses
  alias BolognesaWeb.Library.Index.State.Library, as: LibraryState

  @spec call(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def call(socket, params) do
    changeset = Library.changeset(params)
    if changeset.valid?, do: save(socket, changeset), else: invalid(socket, changeset)
  end

  defp save(socket, changeset) do
    attrs = Map.take(Ecto.Changeset.apply_changes(changeset), [:name, :path, :content_type])

    case Libraries.create_library(socket.assigns.current_scope.actor, attrs) do
      {:ok, library} ->
        socket
        |> BolognesaWeb.LibraryNavigation.refresh()
        |> CancelScanStatuses.call()
        |> assign(:form, to_form(Library.changeset()))
        |> assign(:error, nil)
        |> assign(
          :success,
          gettext("Biblioteca guardada. La carpeta todavía no se ha escaneado.")
        )
        |> stream_insert(
          :libraries,
          LibraryState.from_domain(library, %ScanStatus{library_id: library.id})
        )
        |> FetchScanStatuses.call()

      {:error, reason} ->
        socket
        |> assign(:error, message(reason))
        |> assign(:success, nil)
        |> assign(:form, to_form(%{changeset | action: :insert}))
    end
  end

  defp invalid(socket, changeset) do
    socket
    |> assign(:error, nil)
    |> assign(:success, nil)
    |> assign(:form, to_form(%{changeset | action: :insert}))
  end

  defp message(:duplicate_source),
    do:
      gettext(
        "Esta carpeta ya está registrada. Usa la biblioteca existente o elige otra carpeta."
      )

  defp message(:source_inaccessible),
    do:
      gettext(
        "No se puede leer la carpeta. Comprueba que la ruta sea absoluta, esté bien escrita y que la carpeta exista y tenga permisos de lectura para Bolognesa. En Docker, usa la ruta de destino del montaje dentro del contenedor."
      )

  defp message(:source_outside_roots),
    do:
      gettext(
        "La carpeta está fuera de las ubicaciones permitidas. Elige una carpeta dentro de BOLOGNESA_LIBRARY_ROOTS o pide al administrador que revise esa configuración. En Docker, debe coincidir con la ruta de destino del montaje dentro del contenedor."
      )

  defp message(:invalid_name), do: gettext("Introduce un nombre válido.")
  defp message(:invalid_content_type), do: gettext("Selecciona películas, series o música.")

  defp message(:invalid_path),
    do:
      gettext(
        "Introduce una ruta absoluta válida. Comprueba cómo está escrita; en Docker, usa la ruta dentro del contenedor."
      )

  defp message(_),
    do:
      gettext(
        "No se ha podido guardar la biblioteca por un error inesperado. Si persiste, informa de la versión de Bolognesa, la hora del fallo y los pasos para reproducirlo. Omite credenciales, rutas privadas y nombres de archivos."
      )
end

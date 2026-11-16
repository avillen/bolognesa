defmodule BolognesaWeb.Library.Index.Reducer.StartScan do
  @moduledoc false
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 3]

  alias Bolognesa.Libraries
  alias BolognesaWeb.Library.Index.ScanStatuses
  alias BolognesaWeb.Params

  @spec call(Phoenix.LiveView.Socket.t(), String.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def call(socket, web_id, opts \\ []) do
    socket = ScanStatuses.cancel(socket)

    with {:ok, id} <- parse_id(web_id),
         {:ok, _scan} <- Libraries.start_scan(socket.assigns.current_scope.actor, id, opts) do
      assign(socket, :scan_feedback, nil)
    else
      {:error, reason} -> assign(socket, :scan_feedback, message(reason))
    end
  end

  defp parse_id(id) do
    case Params.positive_integer(id) do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  defp message(:not_found), do: gettext("No se encontró la biblioteca.")
  defp message(:forbidden), do: gettext("No tienes permiso para escanear esta biblioteca.")
  defp message(:scan_in_progress), do: gettext("Esta biblioteca ya tiene un escaneo activo.")
  defp message(_), do: gettext("No se pudo solicitar el escaneo. Vuelve a intentarlo.")
end

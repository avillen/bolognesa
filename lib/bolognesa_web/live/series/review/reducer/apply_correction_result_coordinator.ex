defmodule BolognesaWeb.Series.Review.Reducer.ApplyCorrectionResultCoordinator do
  @moduledoc "Applies a correction result and, once saved, reloads the review list."
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.Component, only: [assign: 2]
  alias BolognesaWeb.Series.Review.AsyncRequest
  alias BolognesaWeb.Series.Review.Reducer.Load

  @spec call(Phoenix.LiveView.Socket.t(), reference(), {:ok, term()} | {:exit, term()}) ::
          Phoenix.LiveView.Socket.t()
  def call(socket, ref, result) do
    case AsyncRequest.complete(socket, :correction, ref) do
      {:ok, socket} -> apply_result(socket, result)
      :stale -> socket
    end
  end

  defp apply_result(socket, {:ok, {:ok, _}}) do
    socket
    |> assign(saving?: false, feedback: gettext("Identificación guardada."))
    |> Load.call(socket.assigns.page, socket.assigns.selected_file_id)
  end

  defp apply_result(socket, {:ok, {:error, :source_changed}}),
    do:
      assign(socket,
        saving?: false,
        feedback: gettext("El archivo ha cambiado. Recarga antes de corregirlo.")
      )

  defp apply_result(socket, {:ok, {:error, :invalid_response}}),
    do:
      assign(socket,
        saving?: false,
        feedback: gettext("TMDb ha movido estos episodios a otra temporada o número.")
      )

  defp apply_result(socket, _),
    do:
      assign(socket,
        saving?: false,
        feedback: gettext("No se pudo guardar la selección completa. Vuelve a intentarlo.")
      )
end

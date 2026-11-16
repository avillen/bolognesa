defmodule BolognesaWeb.Music.Index.Reducer.RetryImportCoordinator do
  @moduledoc "Retries an audio import and, once queued, reloads the list."
  use Gettext, backend: BolognesaWeb.Gettext
  import Phoenix.LiveView, only: [put_flash: 3]
  alias Bolognesa.Music
  alias BolognesaWeb.Music.Index.Reducer.Load
  alias BolognesaWeb.Params
  @spec call(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket, file_text) do
    with file_id when is_integer(file_id) <- Params.positive_integer(file_text),
         :ok <- Music.retry_import(socket.assigns.current_scope.actor, file_id) do
      socket
      |> put_flash(:info, gettext("Importación de audio en cola."))
      |> Load.call(socket.assigns.query, socket.assigns.page)
    else
      _error -> put_flash(socket, :error, gettext("No se pudo reintentar la importación."))
    end
  end
end

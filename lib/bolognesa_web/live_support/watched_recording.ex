defmodule BolognesaWeb.LiveSupport.WatchedRecording do
  @moduledoc """
  Correlates client-qualified watched reports with the current playback attempt and file,
  and deduplicates successful saves per attempt in the `:watched_attempt_id` assign.
  """
  import Phoenix.Component, only: [assign: 3]
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias BolognesaWeb.Params

  @type recorder ::
          (AuthenticatedUser.t(), pos_integer(), pos_integer() -> :ok | {:error, atom()})

  @doc "Records through `recorder` with the content id and file; replies whether this attempt is saved."
  @spec handle_event(map(), Phoenix.LiveView.Socket.t(), recorder()) ::
          {:reply, %{ok: boolean()}, Phoenix.LiveView.Socket.t()}
  def handle_event(params, socket, recorder) do
    socket = record(socket, params, recorder)
    {:reply, %{ok: socket.assigns.watched_attempt_id == params["attempt_id"]}, socket}
  end

  defp record(socket, %{"attempt_id" => id, "file_id" => text}, recorder) when is_binary(id) do
    with false <- socket.assigns.loading?,
         %{id: ^id, phase: :ready, error: nil, file_id: file_id} <- socket.assigns.playback,
         ^file_id <- Params.positive_integer(text),
         false <- socket.assigns.watched_attempt_id == id,
         {_kind, content_id} = socket.assigns.content_ref,
         :ok <- recorder.(socket.assigns.current_scope.actor, content_id, file_id) do
      assign(socket, :watched_attempt_id, id)
    else
      _ -> socket
    end
  end

  defp record(socket, _params, _recorder), do: socket
end

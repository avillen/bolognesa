defmodule BolognesaWeb.Series.Review.AsyncRequest do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [start_async: 3, cancel_async: 2]
  @spec start(Phoenix.LiveView.Socket.t(), atom(), (-> term())) :: Phoenix.LiveView.Socket.t()
  def start(socket, kind, operation) do
    socket = cancel(socket, kind)
    ref = make_ref()

    socket
    |> assign(requests: Map.put(socket.assigns.requests, kind, ref))
    |> start_async({kind, ref}, operation)
  end

  @spec cancel(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  def cancel(socket, kind) do
    case Map.get(socket.assigns.requests, kind) do
      nil -> socket
      ref -> cancel_async(socket, {kind, ref})
    end
  end

  @doc "Removes a finished request, or returns `:stale` when a newer one replaced it."
  @spec complete(Phoenix.LiveView.Socket.t(), atom(), reference()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | :stale
  def complete(socket, kind, ref) do
    if Map.get(socket.assigns.requests, kind) == ref,
      do: {:ok, assign(socket, requests: Map.delete(socket.assigns.requests, kind))},
      else: :stale
  end
end

defmodule BolognesaWeb.Series.Season.Reducer.Initialize do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 3]
  @spec call(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def call(socket),
    do:
      socket
      |> assign(
        detail: nil,
        loading?: true,
        error: nil,
        content_id: 0,
        page: 1,
        total: 0,
        request_id: nil
      )
      |> stream(:episodes, [])
end

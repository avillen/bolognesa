defmodule BolognesaWeb.Series.Show.Reducer.ApplyContinueTarget do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  alias Bolognesa.Series.Domain.ReadModels.ContinueTarget

  @spec call(
          Phoenix.LiveView.Socket.t(),
          integer(),
          {:ok, {:ok, ContinueTarget.t() | nil} | {:error, term()}} | {:exit, term()}
        ) :: Phoenix.LiveView.Socket.t()
  def call(%{assigns: %{content_id: id}} = socket, id, {:ok, {:ok, target}}),
    do: assign(socket, continue_target: target)

  def call(socket, _id, _result), do: socket
end

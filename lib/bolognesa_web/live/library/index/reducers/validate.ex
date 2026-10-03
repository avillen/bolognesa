defmodule BolognesaWeb.Library.Index.Reducers.Validate do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  alias BolognesaWeb.Library.Index.Forms.Library

  @spec call(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def call(socket, params) do
    changeset = Library.changeset(params)
    assign(socket, :form, to_form(%{changeset | action: :validate}))
  end
end

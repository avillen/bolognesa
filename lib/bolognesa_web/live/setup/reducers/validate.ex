defmodule BolognesaWeb.Setup.Reducers.Validate do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  alias BolognesaWeb.Setup.Forms.Admin

  def call(socket, params) do
    changeset = Admin.changeset(params) |> Map.put(:action, :validate)
    assign(socket, :form, to_form(changeset))
  end
end

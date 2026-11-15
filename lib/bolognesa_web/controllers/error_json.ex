defmodule BolognesaWeb.ErrorJSON do
  alias Phoenix.Controller

  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  @spec render(String.t(), map()) :: %{errors: %{detail: String.t()}}
  def render(template, _assigns) do
    %{errors: %{detail: Controller.status_message_from_template(template)}}
  end
end

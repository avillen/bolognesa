defmodule Bolognesa.Identity.Domain.Actor do
  @moduledoc "The verified identity passed to protected use cases."
  defstruct [:id, :name, :email, :role]

  @type t :: %__MODULE__{id: integer(), name: String.t(), email: String.t(), role: atom()}
end

defmodule Bolognesa.Identity.Domain.Actor do
  @moduledoc "The verified identity passed to protected use cases."
  defstruct [:id, :name, :email, :role]

  @type t :: %__MODULE__{id: integer(), name: String.t(), email: String.t(), role: atom()}

  alias Bolognesa.Identity.Domain.User

  @spec from_user(User.t()) :: t()
  def from_user(%User{} = user) do
    %__MODULE__{id: user.id, name: user.name, email: user.email, role: user.role}
  end
end

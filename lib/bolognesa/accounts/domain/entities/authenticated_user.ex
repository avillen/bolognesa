defmodule Bolognesa.Accounts.Domain.Entities.AuthenticatedUser do
  @moduledoc "The verified identity passed to protected use cases."
  alias Bolognesa.Accounts.Domain.ValueObjects.Locale

  alias Bolognesa.Accounts.Domain.Entities.User

  @type t :: %__MODULE__{
          id: User.id(),
          name: User.name(),
          email: User.email(),
          role: :admin | :member,
          locale: Locale.t()
        }

  defstruct [:id, :name, :email, :role, :locale]

  @spec from_user(User.t()) :: t()
  def from_user(%User{} = user) do
    %__MODULE__{
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      locale: user.locale
    }
  end
end

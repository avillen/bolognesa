defmodule Bolognesa.Identity.Domain.Entities.User do
  @moduledoc "A persisted user with an assigned identity."
  alias Bolognesa.Identity.Domain.ValueObjects.Locale

  @type id :: pos_integer()
  @type name :: String.t()
  @type email :: String.t()
  @type password :: String.t()

  @type t :: %__MODULE__{
          id: id(),
          name: name(),
          email: email(),
          role: :admin | :member,
          locale: Locale.t()
        }

  defstruct [:id, :name, :email, :role, :locale]
end

defmodule Bolognesa.Identity.Infrastructure.Persistence.UserMapper do
  @moduledoc false
  alias Bolognesa.Identity.Domain.User

  def to_user(schema) do
    %User{
      id: schema.id,
      name: schema.name,
      email: schema.email,
      role: String.to_existing_atom(schema.role)
    }
  end
end

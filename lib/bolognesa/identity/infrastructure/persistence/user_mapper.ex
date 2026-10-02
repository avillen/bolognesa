defmodule Bolognesa.Identity.Infrastructure.Persistence.UserMapper do
  @moduledoc false
  alias Bolognesa.Identity.Domain.{Actor, User}

  def to_user(schema) do
    %User{
      id: schema.id,
      name: schema.name,
      email: schema.email,
      role: String.to_existing_atom(schema.role)
    }
  end

  def to_actor(%User{} = user) do
    %Actor{id: user.id, name: user.name, email: user.email, role: user.role}
  end
end

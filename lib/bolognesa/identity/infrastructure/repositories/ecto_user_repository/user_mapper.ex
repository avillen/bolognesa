defmodule Bolognesa.Identity.Infrastructure.Repositories.EctoUserRepository.UserMapper do
  @moduledoc false
  alias Bolognesa.Identity.Domain.Entities.User
  alias Bolognesa.Infrastructure.Persistence.UserSchema

  @spec to_user(UserSchema.t()) :: User.t()
  def to_user(schema) do
    %User{
      id: schema.id,
      name: schema.name,
      email: schema.email,
      role: String.to_existing_atom(schema.role)
    }
  end
end

defmodule Bolognesa.Accounts.Infrastructure.Repositories.EctoUserRepository.UserMapper do
  @moduledoc false
  alias Bolognesa.Accounts.Domain.Entities.User
  alias Bolognesa.Infrastructure.Persistence.UserSchema

  @spec to_user(UserSchema.t()) :: User.t()
  def to_user(schema) do
    %User{
      id: schema.id,
      name: schema.name,
      email: schema.email,
      role: role(schema.role),
      locale: schema.locale
    }
  end

  defp role("admin"), do: :admin
  defp role("member"), do: :member
end

defmodule Bolognesa.Accounts.Infrastructure.Repositories.EctoUserRepository.SessionMapper do
  @moduledoc false
  alias Bolognesa.Accounts.Domain.Entities.User

  alias Bolognesa.Accounts.Infrastructure.Repositories.EctoUserRepository.UserMapper
  alias Bolognesa.Infrastructure.Persistence.SessionSchema

  @spec to_user(SessionSchema.t()) :: User.t()
  def to_user(%{user: user}), do: UserMapper.to_user(user)
end

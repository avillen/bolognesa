defmodule Bolognesa.Identity.Infrastructure.Repositories.EctoUserRepository.SessionMapper do
  @moduledoc false
  alias Bolognesa.Identity.Domain.User

  alias Bolognesa.Identity.Infrastructure.Repositories.EctoUserRepository.UserMapper
  alias Bolognesa.Infrastructure.Persistence.SessionSchema

  @spec to_user(SessionSchema.t()) :: User.t()
  def to_user(%{user: user}), do: UserMapper.to_user(user)
end

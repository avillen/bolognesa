defmodule Bolognesa.Identity.Infrastructure.Persistence.EctoUserRepository.SessionMapper do
  @moduledoc false
  alias Bolognesa.Identity.Domain.User

  alias Bolognesa.Identity.Infrastructure.Persistence.EctoUserRepository.{
    SessionSchema,
    UserMapper
  }

  @spec to_user(SessionSchema.t()) :: User.t()
  def to_user(%{user: user}), do: UserMapper.to_user(user)
end

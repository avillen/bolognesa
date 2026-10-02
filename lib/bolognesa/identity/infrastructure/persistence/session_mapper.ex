defmodule Bolognesa.Identity.Infrastructure.Persistence.SessionMapper do
  @moduledoc false
  alias Bolognesa.Identity.Domain.User
  alias Bolognesa.Identity.Infrastructure.Persistence.SessionSchema
  alias Bolognesa.Identity.Infrastructure.Persistence.UserMapper

  @spec to_user(%SessionSchema{}) :: User.t()
  def to_user(%{user: user}), do: UserMapper.to_user(user)
end

defmodule Bolognesa.Identity.Infrastructure.Persistence.SessionMapper do
  @moduledoc false
  alias Bolognesa.Identity.Infrastructure.Persistence.UserMapper

  def to_user(%{user: user}), do: UserMapper.to_user(user)
end

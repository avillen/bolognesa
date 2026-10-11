defmodule Bolognesa.Identity.Application.Ports.Services.PasswordHasher do
  @moduledoc "Password hashing boundary for identity use cases."
  alias Bolognesa.Identity.Domain.User

  @typedoc "Module implementing the password hasher behaviour."
  @type adapter :: atom()
  @type hash :: String.t()

  @callback hash(User.password()) :: hash()
  @callback verify(User.password(), hash()) :: boolean()
  @callback dummy_verify(User.password()) :: :ok
end

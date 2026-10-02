defmodule Bolognesa.Identity.Application.Ports.PasswordHasher do
  @moduledoc "Password hashing boundary for identity use cases."
  @callback hash(binary()) :: binary()
  @callback verify(binary(), binary()) :: boolean()
  @callback dummy_verify(binary()) :: :ok
end

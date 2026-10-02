defmodule Bolognesa.Identity.Infrastructure.BcryptHasher do
  @moduledoc false
  @behaviour Bolognesa.Identity.Application.Ports.PasswordHasher

  @impl true
  def hash(password), do: Bcrypt.hash_pwd_salt(password)

  @impl true
  def verify(password, hash), do: Bcrypt.verify_pass(password, hash)

  @impl true
  def dummy_verify(_password), do: Bcrypt.no_user_verify()
end

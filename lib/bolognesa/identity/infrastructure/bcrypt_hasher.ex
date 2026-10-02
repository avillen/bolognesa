defmodule Bolognesa.Identity.Infrastructure.BcryptHasher do
  @moduledoc false
  @behaviour Bolognesa.Identity.Application.Ports.PasswordHasher

  def hash(password), do: Bcrypt.hash_pwd_salt(password)
  def verify(password, hash), do: Bcrypt.verify_pass(password, hash)
  def dummy_verify(_password), do: Bcrypt.no_user_verify()
end

defmodule Bolognesa.Accounts.PasswordHasherTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Accounts.Infrastructure.Services.BcryptHasher

  test "dummy verification conforms to the port result" do
    assert :ok = BcryptHasher.dummy_verify("example")
  end
end

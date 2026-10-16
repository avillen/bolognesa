defmodule Bolognesa.Accounts.NewAdminTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Accounts.Domain.ValueObjects.Sessions.NewAdmin

  test "a validated administrator registration normalizes identity and redacts its password" do
    password = "correct horse battery staple"

    assert {:ok, %NewAdmin{} = registration} =
             NewAdmin.new(%{name: " Ada ", email: " ADA@Example.COM ", password: password})

    assert registration.name == "Ada"
    assert registration.email == "ada@example.com"
    assert registration.password == password
    refute inspect(registration) =~ password
  end
end

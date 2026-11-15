defmodule Bolognesa.Accounts.UserMapperTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Accounts.Infrastructure.Repositories.EctoUserRepository.UserMapper
  alias Bolognesa.Infrastructure.Persistence.UserSchema

  test "persisted roles map to domain roles" do
    for {stored, role} <- [{"admin", :admin}, {"member", :member}] do
      schema = %UserSchema{
        id: 1,
        name: "Sample",
        email: "sample@example.com",
        role: stored,
        locale: "en"
      }

      assert UserMapper.to_user(schema).role == role
    end
  end
end

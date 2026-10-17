defmodule Bolognesa.Accounts.UserMapperTest do
  use ExUnit.Case, async: true

  test "persisted roles can be mapped in a fresh VM before domain modules are loaded" do
    script = """
    mapper = Module.concat(["Bolognesa", "Accounts", "Infrastructure", "Repositories", "EctoUserRepository", "UserMapper"])
    for role <- ["admin", "member"] do
      user = apply(mapper, :to_user, [%{id: 1, name: "Sample", email: "sample@example.com", role: role, locale: "en"}])
      if Atom.to_string(user.role) != role, do: raise("role mismatch")
    end
    """

    paths = Enum.flat_map(Path.wildcard("_build/test/lib/*/ebin"), &["-pa", Path.expand(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["--erl", "+S 2:2"] ++ paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end

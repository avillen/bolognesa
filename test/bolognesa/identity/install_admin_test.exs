defmodule Bolognesa.Identity.InstallAdminTest do
  use Bolognesa.DataCase, async: false
  alias Ecto.Adapters.SQL.Sandbox

  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Infrastructure.Persistence.UserSchema

  @password "correct horse battery staple"

  test "the first valid administrator is stored with a normalized email and a password hash" do
    assert {:ok, :open} = Identity.setup_status()

    assert {:ok, %Actor{} = actor} =
             Identity.install_admin(%{
               name: "Ada",
               email: "  ADA@Example.COM ",
               password: @password
             })

    assert actor.name == "Ada"
    assert actor.email == "ada@example.com"
    assert actor.role == :admin
    assert {:ok, :closed} = Identity.setup_status()

    stored = Repo.one!(UserSchema)
    assert stored.id == actor.id
    assert stored.email == actor.email
    assert stored.hashed_password != @password
    assert Bcrypt.verify_pass(@password, stored.hashed_password)
  end

  test "the release console binds the administrator actor at startup" do
    {_result, bindings} = Code.eval_file("rel/overlays/bin/.iex.exs")
    assert bindings[:admin] == nil

    assert {:ok, installed} =
             Identity.install_admin(%{name: "Ada", email: "ada@example.com", password: @password})

    {_result, bindings} = Code.eval_file("rel/overlays/bin/.iex.exs")
    assert %Actor{} = bindings[:admin]
    assert bindings[:admin] == installed
    refute Map.has_key?(Map.from_struct(bindings[:admin]), :hashed_password)
  end

  test "invalid identity and password input leave setup open" do
    for attrs <- [
          %{name: "", email: "ada@example.com", password: @password},
          %{name: "Ada", email: " ", password: @password},
          %{name: "Ada", email: "invalid", password: @password},
          %{name: "Ada", email: "àda@example.com", password: @password},
          %{name: "Ada", email: "K@example.com", password: @password},
          %{name: "Ada", email: "ada@example.com", password: "too short"},
          %{name: "Ada", email: "ada@example.com", password: String.duplicate("a", 73)},
          %{name: "Ada", email: "ada@example.com", password: "a\0" <> String.duplicate("b", 11)}
        ] do
      assert {:error, {:invalid, errors}} = Identity.install_admin(attrs)
      assert map_size(errors) > 0
      assert {:ok, :open} = Identity.setup_status()
    end

    assert Repo.aggregate(UserSchema, :count) == 0
  end

  test "administrator attributes use atom keys after the web form is parsed" do
    assert {:error, {:invalid, errors}} =
             Identity.install_admin(%{
               "name" => "Ada",
               "email" => "ada@example.com",
               "password" => @password
             })

    assert Map.keys(errors) |> Enum.sort() == [:email, :name, :password]
    assert {:ok, :open} = Identity.setup_status()
  end

  test "setup closes after the first administrator and rejects another email" do
    assert {:ok, _} =
             Identity.install_admin(%{name: "Ada", email: "ada@example.com", password: @password})

    assert {:error, :setup_closed} =
             Identity.install_admin(%{
               name: "Other",
               email: "other@example.com",
               password: @password
             })

    assert Repo.aggregate(UserSchema, :count) == 1
  end

  test "two simultaneous setup submissions create exactly one administrator" do
    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    # Each unboxed task gets a separate committed database connection. Shared
    # sandbox ownership would serialize both attempts on a single connection.
    Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(UserSchema) end)

    try do
      tasks =
        for email <- ["one@example.com", "two@example.com"] do
          Task.Supervisor.async_nolink(supervisor, fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:ready, self()})

              receive do
                :go -> Identity.install_admin(%{name: "Admin", email: email, password: @password})
              end
            end)
          end)
        end

      pids =
        for _ <- tasks do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(pids, &send(&1, :go))

      results =
        tasks
        |> Enum.map(&Task.await/1)
        |> Enum.map(fn
          {:ok, _} -> :ok
          {:error, reason} -> reason
        end)

      assert Enum.sort(results) == [:ok, :setup_closed]

      assert Sandbox.unboxed_run(Repo, fn ->
               Repo.aggregate(UserSchema, :count)
             end) == 1
    after
      Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(UserSchema) end)
    end
  end

  test "only an administrator actor is authorized for administrator actions" do
    assert :ok =
             Identity.authorize(
               %Actor{id: 1, name: "Ada", email: "ada@example.com", role: :admin},
               :admin
             )

    assert {:error, :forbidden} = Identity.authorize(%Actor{id: 2, role: :member}, :admin)
    assert {:error, :forbidden} = Identity.authorize(nil, :admin)
  end
end

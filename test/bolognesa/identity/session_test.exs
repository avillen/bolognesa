defmodule Bolognesa.Identity.SessionTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Infrastructure.Persistence.SessionSchema

  @password "correct horse battery staple"

  setup do
    {:ok, actor} =
      Identity.install_admin(%{name: "Ada", email: "ada@example.com", password: @password})

    %{actor: actor}
  end

  test "valid credentials create a random session that resolves to the administrator", %{
    actor: actor
  } do
    assert {:ok, token} = Identity.start_session(" ADA@Example.COM ", @password)
    assert is_binary(token)
    assert byte_size(token) == 43
    assert {:ok, %Actor{id: actor_id, email: "ada@example.com"}} = Identity.fetch_actor(token)
    assert actor_id == actor.id
    assert stored = Repo.one!(SessionSchema)
    refute stored.token_hash == token
    refute inspect(stored) =~ token
    assert DateTime.diff(stored.expires_at, stored.inserted_at, :second) == 30 * 24 * 60 * 60
  end

  test "unknown email and wrong password have the same result" do
    assert {:error, :invalid_credentials} =
             Identity.start_session("missing@example.com", @password)

    assert {:error, :invalid_credentials} =
             Identity.start_session("ada@example.com", "wrong password")

    assert Repo.aggregate(SessionSchema, :count) == 0
  end

  test "a NUL suffix cannot authenticate as the password prefix" do
    assert {:error, :invalid_credentials} =
             Identity.start_session("ada@example.com", @password <> "\0suffix")

    assert Repo.aggregate(SessionSchema, :count) == 0
  end

  test "each device has a distinct token and logout revokes only that token" do
    assert {:ok, first} = Identity.start_session("ada@example.com", @password)
    assert {:ok, second} = Identity.start_session("ada@example.com", @password)
    assert first != second
    assert :ok = Identity.end_session(first)
    assert {:error, :unauthenticated} = Identity.fetch_actor(first)
    assert {:ok, %Actor{email: "ada@example.com"}} = Identity.fetch_actor(second)
  end

  test "an expired token does not resolve even when its row remains" do
    assert {:ok, token} = Identity.start_session("ada@example.com", @password)
    session = Repo.one!(SessionSchema)

    session
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update!()

    assert {:error, :unauthenticated} = Identity.fetch_actor(token)
  end

  test "malformed and missing tokens never resolve" do
    for token <- [nil, "", "invalid", String.duplicate("!", 43), String.duplicate("a", 1000)] do
      assert {:error, :unauthenticated} = Identity.fetch_actor(token)
    end
  end

  test "a padded version of a valid token is rejected" do
    assert {:ok, token} = Identity.start_session("ada@example.com", @password)
    assert {:error, :unauthenticated} = Identity.fetch_actor(token <> "=")
  end
end

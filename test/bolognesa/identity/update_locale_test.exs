defmodule Bolognesa.Identity.UpdateLocaleTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identity
  alias Bolognesa.Infrastructure.Persistence.UserSchema

  @password "correct horse battery staple"

  setup do
    {:ok, actor} =
      Identity.install_admin(%{name: "Ada", email: "ada@example.com", password: @password})

    %{actor: actor}
  end

  test "preference persists across devices and automatic restores nil", %{actor: actor} do
    {:ok, first} = Identity.start_session("ada@example.com", @password)
    {:ok, second} = Identity.start_session("ada@example.com", @password)
    assert {:ok, %{locale: "en"}} = Identity.update_locale(actor, "en")
    assert {:ok, %{locale: "en"}} = Identity.fetch_actor(first)
    assert {:ok, %{locale: "en"}} = Identity.fetch_actor(second)
    assert {:ok, %{locale: "es"}} = Identity.update_locale(actor, "es")
    assert {:ok, %{locale: nil}} = Identity.update_locale(actor, nil)
    assert {:ok, %{locale: nil}} = Identity.fetch_actor(first)
  end

  test "invalid values and anonymous actors never write", %{actor: actor} do
    assert {:ok, _} = Identity.update_locale(actor, "en")

    for value <- ["fr", "", "en-US", %{}, ["en"]] do
      assert {:error, :invalid_locale} = Identity.update_locale(actor, value)
    end

    assert {:error, :forbidden} = Identity.update_locale(nil, "es")
    assert Repo.get!(UserSchema, actor.id).locale == "en"
  end

  test "only the actor preference changes and credentials remain usable", %{actor: actor} do
    original = Repo.get!(UserSchema, actor.id)

    other =
      Repo.insert!(%UserSchema{
        name: "Other",
        email: "other@example.com",
        role: "member",
        hashed_password: "unused"
      })

    assert {:ok, _} = Identity.update_locale(actor, "en")
    updated = Repo.get!(UserSchema, actor.id)
    assert updated.hashed_password == original.hashed_password
    assert updated.role == original.role
    assert updated.email == original.email
    assert Repo.get!(UserSchema, other.id).locale == nil
    assert {:ok, _} = Identity.start_session("ada@example.com", @password)
  end

  test "database rejects unsupported locales", %{actor: actor} do
    changeset =
      Repo.get!(UserSchema, actor.id)
      |> Ecto.Changeset.change(locale: "fr")
      |> Ecto.Changeset.check_constraint(:locale, name: :identity_users_locale_valid)

    assert {:error, changeset} = Repo.update(changeset)
    assert Keyword.has_key?(changeset.errors, :locale)
  end
end

defmodule Bolognesa.Accounts.Infrastructure.Repositories.EctoUserRepository do
  @moduledoc false
  @behaviour Bolognesa.Accounts.Application.Ports.Repositories.UserRepository

  import Ecto.Query
  alias Bolognesa.Repo

  alias Bolognesa.Accounts.Infrastructure.Repositories.EctoUserRepository.UserMapper

  alias Bolognesa.Infrastructure.Persistence.SessionSchema
  alias Bolognesa.Infrastructure.Persistence.UserSchema

  @impl true
  def update_locale(user_id, locale) do
    query = from u in UserSchema, where: u.id == ^user_id, select: u

    case Repo.update_all(query, [set: [locale: locale, updated_at: DateTime.utc_now()]],
           log: false
         ) do
      {1, [stored]} -> {:ok, UserMapper.to_user(stored)}
      {0, _} -> {:error, :not_found}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  @impl true
  def admin_exists? do
    {:ok, Repo.exists?(from u in UserSchema, where: u.role == "admin")}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  @impl true
  def insert_initial_admin(user, hashed_password) do
    attrs = %{name: user.name, email: user.email}
    record = %UserSchema{role: "admin", hashed_password: hashed_password}

    case record |> UserSchema.changeset(attrs) |> Repo.insert(log: false) do
      {:ok, stored} -> {:ok, UserMapper.to_user(stored)}
      {:error, changeset} -> {:error, map_insert_error(changeset)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  @impl true
  def fetch_user_by_email(email) do
    case Repo.get_by(UserSchema, [email: email], log: false) do
      nil -> :not_found
      stored -> {:ok, {UserMapper.to_user(stored), stored.hashed_password}}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  @impl true
  def fetch_admin do
    case Repo.one(from u in UserSchema, where: u.role == "admin") do
      nil -> :not_found
      stored -> {:ok, UserMapper.to_user(stored)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  @impl true
  def insert_session(session) do
    Repo.delete_all(from(s in SessionSchema, where: s.expires_at <= ^session.issued_at),
      log: false
    )

    case Repo.insert(
           %SessionSchema{
             user_id: session.user_id,
             token_hash: session.token_hash,
             expires_at: session.expires_at,
             inserted_at: session.issued_at
           },
           log: false
         ) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :unavailable}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  @impl true
  def fetch_active_session(token_hash, now) do
    query =
      from s in SessionSchema,
        join: u in assoc(s, :user),
        where: s.token_hash == ^token_hash and s.expires_at > ^now,
        select: u

    case Repo.one(query, log: false) do
      nil -> :not_found
      stored -> {:ok, UserMapper.to_user(stored)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  @impl true
  def delete_session(token_hash) do
    case Repo.delete_all(from(s in SessionSchema, where: s.token_hash == ^token_hash), log: false) do
      {0, _} -> {:ok, :not_found}
      {_count, _} -> {:ok, :deleted}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  defp map_insert_error(changeset) do
    # The email index can fire before accounts_one_admin when the admin's email is reused.
    if admin_constraint?(changeset) or
         Repo.exists?(from u in UserSchema, where: u.role == "admin"),
       do: :setup_closed,
       else: :unavailable
  end

  defp admin_constraint?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
      opts[:constraint_name] == "accounts_one_admin"
    end)
  end
end

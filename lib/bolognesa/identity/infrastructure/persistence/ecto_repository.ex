defmodule Bolognesa.Identity.Infrastructure.Persistence.EctoRepository do
  @moduledoc false
  @behaviour Bolognesa.Identity.Application.Ports.Repository

  import Ecto.Query
  alias Bolognesa.Repo

  alias Bolognesa.Identity.Infrastructure.Persistence.{
    SessionMapper,
    SessionSchema,
    UserMapper,
    UserSchema
  }

  def admin_exists? do
    {:ok, Repo.exists?(from u in UserSchema, where: u.role == "admin")}
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  def insert_initial_admin(user, hashed_password) do
    result =
      Repo.transaction(fn ->
        if Repo.exists?(from u in UserSchema, where: u.role == "admin") do
          Repo.rollback(:setup_closed)
        end

        attrs = %{name: user.name, email: user.email}
        record = %UserSchema{role: "admin", hashed_password: hashed_password}

        case record |> UserSchema.changeset(attrs) |> Repo.insert() do
          {:ok, stored} -> UserMapper.to_user(stored)
          {:error, changeset} -> Repo.rollback(map_insert_error(changeset))
        end
      end)

    result
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  def find_user_by_email(email) do
    case Repo.get_by(UserSchema, email: email) do
      nil -> :not_found
      stored -> {:ok, UserMapper.to_user(stored), stored.hashed_password}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  def insert_session(user_id, token_hash, expires_at) do
    inserted_at = DateTime.add(expires_at, -30 * 24 * 60 * 60, :second)

    case Repo.insert(%SessionSchema{
           user_id: user_id,
           token_hash: token_hash,
           expires_at: expires_at,
           inserted_at: inserted_at
         }) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :unavailable}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  def find_active_session(token_hash, now) do
    query =
      from s in SessionSchema,
        where: s.token_hash == ^token_hash and s.expires_at > ^now,
        preload: [:user]

    case Repo.one(query) do
      nil -> :not_found
      session -> {:ok, SessionMapper.to_user(session)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  def delete_session(token_hash) do
    Repo.delete_all(from s in SessionSchema, where: s.token_hash == ^token_hash)
    :ok
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
  end

  defp map_insert_error(changeset) do
    if Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
         opts[:constraint_name] == "identity_one_admin"
       end),
       do: :setup_closed,
       else: :unavailable
  end
end

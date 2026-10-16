defmodule Bolognesa.Repo.Migrations.RenameIdentityToAccounts do
  use Ecto.Migration

  def up, do: rename_storage("identity", "accounts")
  def down, do: rename_storage("accounts", "identity")

  defp rename_storage(previous, current) do
    for suffix <- ["users", "sessions"] do
      execute("ALTER TABLE #{previous}_#{suffix} RENAME TO #{current}_#{suffix}")

      execute("ALTER SEQUENCE #{previous}_#{suffix}_id_seq RENAME TO #{current}_#{suffix}_id_seq")

      execute(
        "ALTER TABLE #{current}_#{suffix} RENAME CONSTRAINT #{previous}_#{suffix}_pkey TO #{current}_#{suffix}_pkey"
      )
    end

    for suffix <- [
          "users_email_index",
          "one_admin",
          "sessions_token_hash_index",
          "sessions_user_id_index"
        ] do
      execute("ALTER INDEX #{previous}_#{suffix} RENAME TO #{current}_#{suffix}")
    end

    for {table, suffix} <- [
          {"users", "users_locale_valid"},
          {"sessions", "sessions_user_id_fkey"}
        ] do
      execute(
        "ALTER TABLE #{current}_#{table} RENAME CONSTRAINT #{previous}_#{suffix} TO #{current}_#{suffix}"
      )
    end
  end
end

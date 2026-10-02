defmodule Bolognesa.Repo.Migrations.CreateIdentitySessions do
  use Ecto.Migration

  def change do
    create table(:identity_sessions) do
      add :user_id, references(:identity_users, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:identity_sessions, [:token_hash])
    create index(:identity_sessions, [:user_id])
  end
end

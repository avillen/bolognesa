defmodule Bolognesa.Repo.Migrations.CreateIdentityTables do
  use Ecto.Migration

  def change do
    create table(:identity_users) do
      add :name, :string, null: false
      add :email, :string, null: false
      add :role, :string, null: false
      add :hashed_password, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:identity_users, [:email])

    create unique_index(:identity_users, [:role],
             where: "role = 'admin'",
             name: :identity_one_admin
           )
  end
end

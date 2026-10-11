defmodule Bolognesa.Repo.Migrations.AddUserLocale do
  use Ecto.Migration

  def change do
    alter table(:identity_users) do
      add :locale, :string
    end

    create constraint(:identity_users, :identity_users_locale_valid,
             check: "locale IS NULL OR locale IN ('es', 'en')"
           )
  end
end

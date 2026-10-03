defmodule Bolognesa.Repo.Migrations.CreateLibraries do
  use Ecto.Migration

  def change do
    create table(:libraries) do
      add :name, :string, null: false
      add :path, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:libraries, [:path])
  end
end

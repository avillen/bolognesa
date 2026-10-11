defmodule Bolognesa.Repo.Migrations.AddLibraryContentType do
  use Ecto.Migration

  def change do
    alter table(:libraries) do
      add :content_type, :string, null: false, default: "movie"
    end

    create constraint(:libraries, :libraries_content_type_valid,
             check: "content_type IN ('movie', 'series')"
           )
  end
end

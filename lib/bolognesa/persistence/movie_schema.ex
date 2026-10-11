defmodule Bolognesa.Persistence.MovieSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: false}
  schema "movies" do
    field :title, :string
    field :original_title, :string
    field :year, :integer
    field :overview, :string
    field :poster_path, :string
    field :backdrop_path, :string
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(movie, attrs) do
    movie
    |> cast(attrs, [
      :title,
      :original_title,
      :year,
      :overview,
      :poster_path,
      :backdrop_path
    ])
    |> validate_required([:title])
    |> validate_length(:title, max: 256)
    |> check_constraint(:title, name: :movies_title_nonempty)
    |> foreign_key_constraint(:id, name: :movies_id_fkey)
  end
end

defmodule Bolognesa.Persistence.MovieSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "movies" do
    field :provider, Ecto.Enum, values: [:tmdb]
    field :provider_id, :integer
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
      :provider,
      :provider_id,
      :title,
      :original_title,
      :year,
      :overview,
      :poster_path,
      :backdrop_path
    ])
    |> validate_required([:provider, :provider_id, :title])
    |> validate_number(:provider_id, greater_than: 0)
    |> validate_length(:title, max: 256)
    |> unique_constraint([:provider, :provider_id])
    |> check_constraint(:provider_id, name: :movies_provider_id_positive)
    |> check_constraint(:title, name: :movies_title_nonempty)
  end
end

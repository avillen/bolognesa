defmodule Bolognesa.Infrastructure.Persistence.MovieSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "movies" do
    field :provider, Ecto.Enum, values: [:tmdb], default: :tmdb
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
    |> unique_constraint([:provider, :provider_id])
    |> check_constraint(:provider, name: :movies_provider_valid)
    |> check_constraint(:provider_id, name: :movies_provider_id_positive)
    |> validate_required([:title, :provider, :provider_id])
    |> validate_length(:title, max: 256)
    |> check_constraint(:title, name: :movies_title_nonempty)
  end
end

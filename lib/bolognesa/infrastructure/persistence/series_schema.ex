defmodule Bolognesa.Infrastructure.Persistence.SeriesSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "series" do
    field :provider, Ecto.Enum, values: [:tmdb], default: :tmdb
    field :provider_id, :integer
    field :title, :string
    field :year, :integer
    field :overview, :string
    field :poster_path, :string
    field :backdrop_path, :string
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> change(attrs)
    |> unique_constraint([:provider, :provider_id])
    |> check_constraint(:provider, name: :series_provider_valid)
    |> check_constraint(:provider_id, name: :series_provider_id_positive)
    |> validate_required([:title, :provider, :provider_id])
  end
end

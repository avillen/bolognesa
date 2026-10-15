defmodule Bolognesa.Infrastructure.Persistence.SeasonSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "seasons" do
    field :provider, Ecto.Enum, values: [:tmdb], default: :tmdb
    field :provider_id, :integer
    field :series_id, :id
    field :number, :integer
    field :title, :string
    field :poster_path, :string
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> change(attrs)
    |> unique_constraint([:provider, :provider_id])
    |> check_constraint(:provider, name: :seasons_provider_valid)
    |> check_constraint(:provider_id, name: :seasons_provider_id_positive)
    |> validate_required([:series_id, :number])
    |> foreign_key_constraint(:series_id)
    |> unique_constraint([:series_id, :number])
    |> check_constraint(:number, name: :seasons_number_valid)
  end
end

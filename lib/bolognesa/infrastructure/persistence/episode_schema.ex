defmodule Bolognesa.Infrastructure.Persistence.EpisodeSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :id, autogenerate: false}
  @type t :: %__MODULE__{}

  schema "episodes" do
    field :season_id, :id
    field :number, :integer
    field :title, :string
    field :overview, :string
    field :air_date, :date
    field :still_path, :string
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> change(attrs)
    |> validate_required([:id, :season_id, :number, :title])
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:season_id)
    |> unique_constraint([:season_id, :number])
    |> check_constraint(:number, name: :episodes_number_valid)
  end
end

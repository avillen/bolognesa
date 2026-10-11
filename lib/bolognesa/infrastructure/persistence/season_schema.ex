defmodule Bolognesa.Infrastructure.Persistence.SeasonSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :id, autogenerate: false}
  @type t :: %__MODULE__{}

  schema "seasons" do
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
    |> validate_required([:id, :series_id, :number])
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:series_id)
    |> unique_constraint([:series_id, :number])
    |> check_constraint(:number, name: :seasons_number_valid)
  end
end

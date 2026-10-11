defmodule Bolognesa.Infrastructure.Persistence.SeriesSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :id, autogenerate: false}
  @type t :: %__MODULE__{}

  schema "series" do
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
    |> validate_required([:id, :title])
    |> foreign_key_constraint(:id)
  end
end

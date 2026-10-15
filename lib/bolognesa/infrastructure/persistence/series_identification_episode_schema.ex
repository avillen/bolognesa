defmodule Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "series_identification_episodes" do
    field :identification_id, :id
    field :episode_id, :id
    field :position, :integer
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> change(attrs)
    |> validate_required([:identification_id, :episode_id, :position])
    |> validate_number(:position, greater_than: 0)
    |> foreign_key_constraint(:identification_id)
    |> foreign_key_constraint(:episode_id)
    |> unique_constraint([:identification_id, :episode_id],
      name: :series_identification_episode_unique
    )
    |> unique_constraint([:identification_id, :position])
    |> check_constraint(:identification_id, name: :series_identification_episodes_confirmed)
    |> check_constraint(:position, name: :series_identification_episodes_position_positive)
  end
end

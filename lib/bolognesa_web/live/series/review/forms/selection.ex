defmodule BolognesaWeb.Series.Review.Forms.Selection do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false
  embedded_schema do
    field :episode_numbers, {:array, :integer}, default: []
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params) do
    %__MODULE__{}
    |> cast(normalize(params), [:episode_numbers])
    |> require_episodes()
    |> validate_required([:episode_numbers])
    |> validate_length(:episode_numbers, min: 1, max: 100)
    |> validate_change(:episode_numbers, fn :episode_numbers, numbers ->
      if Enum.all?(numbers, &(&1 > 0)) and Enum.uniq(numbers) == numbers,
        do: [],
        else: [episode_numbers: "Selecciona episodios válidos sin repetir."]
    end)
  end

  defp require_episodes(changeset) do
    if get_field(changeset, :episode_numbers) == [],
      do: add_error(changeset, :episode_numbers, "Selecciona al menos un episodio."),
      else: changeset
  end

  defp normalize(%{"episode_numbers" => numbers} = params) when is_list(numbers),
    do: Map.put(params, "episode_numbers", Enum.reject(numbers, &(&1 == "")))

  defp normalize(params), do: params
end

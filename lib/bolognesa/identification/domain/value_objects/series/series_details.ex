defmodule Bolognesa.Identification.Domain.ValueObjects.Series.SeriesDetails do
  @moduledoc "Normalized series provider data owned by Identification."
  alias Bolognesa.Identification.Domain.ValueObjects.Series.SeriesCandidate
  defstruct [:provider_id, :title, :year, :overview, :poster_path, :backdrop_path]

  @type t :: %__MODULE__{
          provider_id: pos_integer(),
          title: binary(),
          year: integer() | nil,
          overview: binary() | nil,
          poster_path: binary() | nil,
          backdrop_path: binary() | nil
        }
  @spec new(map()) :: {:ok, t()} | {:error, :invalid_response}
  def new(attrs) do
    case SeriesCandidate.new(attrs) do
      {:ok, candidate} ->
        {:ok,
         %__MODULE__{
           provider_id: candidate.provider_id,
           title: candidate.title,
           year: candidate.year,
           poster_path: candidate.poster_path,
           backdrop_path: SeriesCandidate.image_path(Map.get(attrs, :backdrop_path)),
           overview: optional_overview(Map.get(attrs, :overview))
         }}

      _ ->
        {:error, :invalid_response}
    end
  end

  defp optional_overview(value) when is_binary(value),
    do: if(String.valid?(value) and byte_size(value) <= 2000, do: value, else: nil)

  defp optional_overview(_), do: nil
end

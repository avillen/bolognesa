defmodule Bolognesa.Movies.Domain.ValueObjects.MovieDetails do
  @moduledoc "Bounded catalog details from a provider."

  alias Bolognesa.Movies.Domain.ValueObjects.MovieCandidate

  @type t :: %__MODULE__{
          provider_id: pos_integer(),
          title: String.t(),
          original_title: String.t() | nil,
          year: integer() | nil,
          overview: String.t() | nil,
          poster_path: String.t() | nil,
          backdrop_path: String.t() | nil
        }

  defstruct [
    :provider_id,
    :title,
    :original_title,
    :year,
    :overview,
    :poster_path,
    :backdrop_path
  ]

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_details}
  def new(attrs) do
    case MovieCandidate.new(attrs) do
      {:ok, candidate} ->
        {:ok,
         %__MODULE__{
           provider_id: candidate.provider_id,
           title: candidate.title,
           original_title: candidate.original_title,
           year: candidate.year,
           overview: overview(Map.get(attrs, :overview)),
           poster_path: candidate.poster_path,
           backdrop_path: MovieCandidate.image_path(Map.get(attrs, :backdrop_path))
         }}

      _ ->
        {:error, :invalid_details}
    end
  end

  defp overview(value) when is_binary(value) do
    if String.valid?(value) and byte_size(value) <= 2_000, do: value, else: nil
  end

  defp overview(_value), do: nil
end

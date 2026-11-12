defmodule Bolognesa.Movies.Domain.ValueObjects.NewMovie do
  @moduledoc "Validated movie data before a database identity is assigned."

  @type attrs :: %{
          required(:provider) => :tmdb,
          required(:provider_id) => pos_integer(),
          required(:title) => String.t(),
          optional(:original_title) => String.t() | nil,
          optional(:year) => integer() | nil,
          optional(:overview) => String.t() | nil,
          optional(:poster_path) => String.t() | nil,
          optional(:backdrop_path) => String.t() | nil
        }

  @type t :: %__MODULE__{
          provider: :tmdb,
          provider_id: pos_integer(),
          title: String.t(),
          original_title: String.t() | nil,
          year: integer() | nil,
          overview: String.t() | nil,
          poster_path: String.t() | nil,
          backdrop_path: String.t() | nil
        }

  defstruct [
    :provider,
    :provider_id,
    :title,
    :original_title,
    :year,
    :overview,
    :poster_path,
    :backdrop_path
  ]

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_movie}
  def new(%{provider: :tmdb, provider_id: id, title: title} = attrs)
      when is_integer(id) and id > 0 and is_binary(title) do
    if String.valid?(title) and String.trim(title) != "" and byte_size(title) <= 256 and
         valid_optional_metadata?(attrs) do
      {:ok,
       %__MODULE__{
         provider: :tmdb,
         provider_id: id,
         title: String.trim(title),
         original_title: Map.get(attrs, :original_title),
         year: Map.get(attrs, :year),
         overview: Map.get(attrs, :overview),
         poster_path: Map.get(attrs, :poster_path),
         backdrop_path: Map.get(attrs, :backdrop_path)
       }}
    else
      {:error, :invalid_movie}
    end
  end

  def new(_attrs), do: {:error, :invalid_movie}

  defp valid_optional_metadata?(attrs) do
    year = Map.get(attrs, :year)

    (is_nil(year) or is_integer(year)) and
      Enum.all?([:original_title, :overview, :poster_path, :backdrop_path], fn field ->
        value = Map.get(attrs, field)
        is_nil(value) or (is_binary(value) and String.valid?(value))
      end)
  end
end

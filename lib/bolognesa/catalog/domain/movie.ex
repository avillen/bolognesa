defmodule Bolognesa.Catalog.Domain.Movie do
  @moduledoc "A catalog movie with a stable internal identity and provider reference."

  defstruct [
    :id,
    :provider,
    :provider_id,
    :title,
    :original_title,
    :year,
    :overview,
    :poster_path,
    :backdrop_path
  ]

  @type id :: pos_integer()
  @type provider :: :tmdb
  @type attrs :: %{
          required(:provider) => provider(),
          required(:provider_id) => pos_integer(),
          required(:title) => binary(),
          optional(:original_title) => binary() | nil,
          optional(:year) => integer() | nil,
          optional(:overview) => binary() | nil,
          optional(:poster_path) => binary() | nil,
          optional(:backdrop_path) => binary() | nil
        }
  @type t :: %__MODULE__{
          id: id(),
          provider: provider(),
          provider_id: pos_integer(),
          title: binary(),
          original_title: binary() | nil,
          year: integer() | nil,
          overview: binary() | nil,
          poster_path: binary() | nil,
          backdrop_path: binary() | nil
        }

  @spec new(attrs()) :: {:ok, attrs()} | {:error, :invalid_movie}
  def new(%{provider: :tmdb, provider_id: id, title: title} = attrs)
      when is_integer(id) and id > 0 and is_binary(title) do
    if String.trim(title) == "" or byte_size(title) > 256 do
      {:error, :invalid_movie}
    else
      {:ok, Map.put(attrs, :title, String.trim(title))}
    end
  end

  def new(_attrs), do: {:error, :invalid_movie}
end

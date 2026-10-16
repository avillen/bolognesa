defmodule Bolognesa.Movies.Domain.ValueObjects.MovieCandidate do
  @moduledoc "A bounded movie search candidate from a provider."

  @type t :: %__MODULE__{
          provider_id: pos_integer(),
          title: binary(),
          original_title: binary() | nil,
          year: integer() | nil,
          poster_path: binary() | nil
        }

  defstruct [:provider_id, :title, :original_title, :year, :poster_path]

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_candidate}
  def new(%{provider_id: id, title: title} = attrs)
      when is_integer(id) and id > 0 and is_binary(title) do
    if String.valid?(title) and String.trim(title) != "" and byte_size(title) <= 256 do
      {:ok,
       %__MODULE__{
         provider_id: id,
         title: String.trim(title),
         original_title: optional_text(Map.get(attrs, :original_title), 256),
         year: valid_year(Map.get(attrs, :year)),
         poster_path: image_path(Map.get(attrs, :poster_path))
       }}
    else
      {:error, :invalid_candidate}
    end
  end

  def new(_attrs), do: {:error, :invalid_candidate}

  @spec image_path(binary() | nil) :: binary() | nil
  def image_path(path) when is_binary(path) do
    if byte_size(path) <= 200 and Regex.match?(~r{^/[A-Za-z0-9._/-]+$}, path) and
         not String.contains?(path, ["..", "//"]),
       do: path,
       else: nil
  end

  def image_path(_path), do: nil

  defp optional_text(value, max) when is_binary(value) do
    if String.valid?(value) and byte_size(value) <= max, do: value, else: nil
  end

  defp optional_text(_value, _max), do: nil

  defp valid_year(year) when is_integer(year) and year >= 1800 and year <= 2200, do: year
  defp valid_year(_year), do: nil
end

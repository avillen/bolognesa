defmodule Bolognesa.Music.Infrastructure.Readers.QueryFilters do
  @moduledoc false
  import Ecto.Query, only: [limit: 2, offset: 2]
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Repo

  @doc "Accepts no library or an existing music library."
  @spec library_scope(pos_integer() | nil) :: :ok | {:error, :not_found}
  def library_scope(nil), do: :ok

  def library_scope(id) do
    case Repo.get(LibrarySchema, id, log: false) do
      %{content_type: :music} -> :ok
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Reads one `size` page of an ordered query plus one lookahead row, so callers
  learn whether a next page exists without counting the whole result.
  """
  @spec lookahead_page(Ecto.Queryable.t(), pos_integer(), pos_integer()) :: {[term()], boolean()}
  def lookahead_page(query, page, size) do
    rows =
      query
      |> limit(^(size + 1))
      |> offset(^((page - 1) * size))
      |> Repo.all(log: false)

    {items, rest} = Enum.split(rows, size)
    {items, rest != []}
  end

  @doc "Builds an `ilike` pattern that matches `text` literally anywhere."
  @spec contains_pattern(String.t()) :: String.t()
  def contains_pattern(text) do
    "%" <>
      (text
       |> String.replace("\\", "\\\\")
       |> String.replace("%", "\\%")
       |> String.replace("_", "\\_")) <> "%"
  end
end

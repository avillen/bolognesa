defmodule Bolognesa.Music.Infrastructure.Readers.QueryFilters do
  @moduledoc false
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

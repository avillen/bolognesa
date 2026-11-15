defmodule BolognesaWeb.Params do
  @moduledoc """
  Parses integer web parameters such as IDs and page numbers.

  Each function returns `nil` for missing, malformed, or out-of-range input so
  callers can choose their own fallback.
  """

  @max_page 100_000

  @doc "Parses a positive integer such as an ID."
  @spec positive_integer(term()) :: pos_integer() | nil
  def positive_integer(value) do
    case parse(value) do
      int when is_integer(int) and int > 0 -> int
      _ -> nil
    end
  end

  @doc "Parses an integer within `range`."
  @spec integer(term(), Range.t()) :: integer() | nil
  def integer(value, range) do
    int = parse(value)
    if is_integer(int) and int in range, do: int
  end

  @doc "Parses a catalog page number, falling back to the first page."
  @spec page(term()) :: pos_integer()
  def page(value), do: integer(value, 1..@max_page) || 1

  defp parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse(_value), do: nil
end

defmodule BolognesaWeb.Music.Index.Forms.Filters do
  @moduledoc "URL filter parsing for the music screen."
  @spec from_params(map()) :: {String.t(), pos_integer()}
  def from_params(params), do: {Map.get(params, "query", ""), page(Map.get(params, "page", "1"))}

  defp page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page in 1..100_000 -> page
      _ -> 1
    end
  end

  defp page(_value), do: 1
end

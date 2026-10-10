defmodule Bolognesa.Playback.Domain.ByteRange do
  @moduledoc "Parse a single HTTP bytes range against a known file size."

  @max_integer 9_223_372_036_854_775_807

  @spec parse(binary() | nil, non_neg_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), 200 | 206}}
          | {:error, :invalid | :unsatisfiable}
  def parse(nil, size) when is_integer(size) and size >= 0, do: {:ok, {0, size, 200}}

  def parse("bytes=" <> value, size) when is_integer(size) and size >= 0 do
    case Regex.run(~r/\A(\d*)-(\d*)\z/, value) do
      [_, "", ""] -> {:error, :invalid}
      [_, "", suffix] -> suffix_range(suffix, size)
      [_, start, ""] -> open_range(start, size)
      [_, start, last] -> closed_range(start, last, size)
      _ -> {:error, :invalid}
    end
  end

  def parse(_, _), do: {:error, :invalid}

  defp suffix_range(value, size) do
    with {:ok, suffix} <- number(value) do
      if suffix > 0 and size > 0 do
        length = min(suffix, size)
        {:ok, {size - length, length, 206}}
      else
        {:error, :unsatisfiable}
      end
    end
  end

  defp open_range(value, size) do
    with {:ok, first} <- number(value) do
      if first < size,
        do: {:ok, {first, size - first, 206}},
        else: {:error, :unsatisfiable}
    end
  end

  defp closed_range(first_text, last_text, size) do
    with {:ok, first} <- number(first_text),
         {:ok, last} <- number(last_text) do
      if first < size and last >= first,
        do: {:ok, {first, min(last, size - 1) - first + 1, 206}},
        else: {:error, :unsatisfiable}
    end
  end

  defp number(digits) when byte_size(digits) <= 19 do
    value = String.to_integer(digits)
    if value <= @max_integer, do: {:ok, value}, else: {:error, :invalid}
  end

  defp number(_), do: {:error, :invalid}
end

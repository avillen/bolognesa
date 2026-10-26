defmodule Bolognesa.Series.Domain.ValueObjects.EpisodePart do
  @moduledoc "An optional explicitly numbered physical part of an episode."

  @spec from_path(binary()) :: {:ok, nil | pos_integer()} | {:error, :ambiguous_name}
  def from_path(path) do
    stem = path |> Path.basename() |> Path.rootname()

    case Regex.run(~r/(?:s\d+e\d+|\d+x\d+)(.*)\z/i, stem) do
      [_, suffix] -> from_suffix(suffix)
      nil -> {:ok, nil}
    end
  end

  @spec from_suffix(binary()) :: {:ok, nil | pos_integer()} | {:error, :ambiguous_name}
  def from_suffix(suffix) do
    case Regex.scan(~r/-part/i, suffix) do
      [] -> {:ok, nil}
      [_] -> parse(suffix)
      _ -> {:error, :ambiguous_name}
    end
  end

  defp parse(suffix) do
    case Regex.run(~r/\A-part(\d+)(?:\z|[ ._\[].*)/i, suffix) do
      [_, number] -> validate(String.to_integer(number))
      _ -> {:error, :ambiguous_name}
    end
  end

  defp validate(number) when number in 1..100, do: {:ok, number}
  defp validate(_), do: {:error, :ambiguous_name}
end

defmodule Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalMedia do
  @moduledoc "Normalized technical media properties from a probe."

  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalTrack

  defstruct [:format, :duration_ms, tracks: []]

  @type t :: %__MODULE__{
          format: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          tracks: [TechnicalTrack.t()]
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_data}
  def new(%{tracks: tracks} = attrs) when is_list(tracks) and length(tracks) <= 128 do
    format = Map.get(attrs, :format)
    duration_ms = Map.get(attrs, :duration_ms)

    with true <- valid_format?(format),
         true <- valid_duration?(duration_ms),
         {:ok, normalized_tracks} <- normalize_tracks(tracks) do
      {:ok, %__MODULE__{format: format, duration_ms: duration_ms, tracks: normalized_tracks}}
    else
      _ -> {:error, :invalid_data}
    end
  end

  def new(_), do: {:error, :invalid_data}

  defp normalize_tracks(tracks) do
    Enum.reduce_while(tracks, {:ok, []}, fn attrs, {:ok, acc} ->
      case TechnicalTrack.new(attrs) do
        {:ok, track} -> {:cont, {:ok, [track | acc]}}
        {:error, :invalid_data} = error -> {:halt, error}
      end
    end)
    |> reverse_tracks()
  end

  defp reverse_tracks({:ok, tracks}), do: {:ok, Enum.reverse(tracks)}
  defp reverse_tracks(error), do: error

  defp valid_format?(nil), do: true

  defp valid_format?(value) when is_binary(value),
    do: byte_size(value) in 1..128 and String.valid?(value)

  defp valid_format?(_), do: false

  defp valid_duration?(nil), do: true

  defp valid_duration?(value),
    do: is_integer(value) and value >= 0 and value <= 1_000_000_000_000
end

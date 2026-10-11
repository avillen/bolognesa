defmodule Bolognesa.Libraries.Infrastructure.Services.FfprobeJson do
  @moduledoc false

  alias Bolognesa.Libraries.Domain.TechnicalMedia

  @max_bytes 262_144
  @max_tracks 128

  @spec parse(binary()) :: {:ok, TechnicalMedia.t()} | {:error, :invalid_output}
  def parse(output) when is_binary(output) and byte_size(output) <= @max_bytes do
    with {:ok, %{"format" => format, "streams" => streams}} <- Jason.decode(output),
         true <- is_map(format) and is_list(streams) and length(streams) <= @max_tracks,
         {:ok, duration_ms} <- duration(Map.get(format, "duration")),
         {:ok, tracks} <- tracks(streams),
         {:ok, media} <-
           TechnicalMedia.new(%{
             format: Map.get(format, "format_name"),
             duration_ms: duration_ms,
             tracks: tracks
           }) do
      {:ok, media}
    else
      _ -> {:error, :invalid_output}
    end
  end

  def parse(_), do: {:error, :invalid_output}

  defp duration(nil), do: {:ok, nil}

  defp duration(value) when is_binary(value) and byte_size(value) <= 32 do
    case Float.parse(value) do
      {seconds, ""} when seconds >= 0 and seconds <= 1_000_000_000 ->
        {:ok, round(seconds * 1_000)}

      _ ->
        {:error, :invalid_output}
    end
  end

  defp duration(_), do: {:error, :invalid_output}

  defp tracks(streams) do
    Enum.reduce_while(streams, {:ok, []}, fn stream, {:ok, acc} ->
      case track(stream) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, attrs} -> {:cont, {:ok, [attrs | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, tracks} -> {:ok, Enum.reverse(tracks)}
      error -> error
    end
  end

  defp track(%{"codec_type" => type} = stream) when type in ["video", "audio", "subtitle"] do
    tags = Map.get(stream, "tags", %{})

    if is_map(tags) do
      {:ok,
       %{
         kind: kind(type),
         codec: Map.get(stream, "codec_name"),
         width: Map.get(stream, "width"),
         height: Map.get(stream, "height"),
         channels: Map.get(stream, "channels"),
         language: Map.get(tags, "language")
       }}
    else
      {:error, :invalid_output}
    end
  end

  defp track(%{"codec_type" => _other}), do: {:ok, nil}
  defp track(_), do: {:error, :invalid_output}

  defp kind("video"), do: :video
  defp kind("audio"), do: :audio
  defp kind("subtitle"), do: :subtitle
end

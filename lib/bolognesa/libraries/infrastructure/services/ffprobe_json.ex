defmodule Bolognesa.Libraries.Infrastructure.Services.FfprobeJson do
  @moduledoc false

  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.{MusicTags, TechnicalMedia}

  @max_bytes 262_144
  @max_tracks 128

  @spec parse(binary(), Bolognesa.Libraries.Domain.Entities.Library.content_type()) ::
          {:ok, TechnicalMedia.t()} | {:error, :invalid_output}
  def parse(output, content_type \\ :movie)

  def parse(output, content_type) when is_binary(output) and byte_size(output) <= @max_bytes do
    with {:ok, %{"format" => format, "streams" => streams}} <- Jason.decode(output),
         true <- is_map(format) and is_list(streams) and length(streams) <= @max_tracks,
         {:ok, duration_ms} <- duration(Map.get(format, "duration")),
         {:ok, tracks} <- tracks(streams, content_type),
         true <- content_type != :music or Enum.any?(tracks, &(&1.kind == :audio)),
         {:ok, media} <-
           TechnicalMedia.new(%{
             format: Map.get(format, "format_name"),
             duration_ms: duration_ms,
             tracks: tracks,
             music_tags: music_tags(format, streams, content_type)
           }) do
      {:ok, media}
    else
      _ -> {:error, :invalid_output}
    end
  end

  def parse(_, _), do: {:error, :invalid_output}

  defp music_tags(format, streams, :music) do
    stream_tags =
      streams
      |> Enum.filter(&(&1["codec_type"] == "audio"))
      |> Enum.reduce(%{}, fn stream, tags -> Map.merge(tags, tag_map(stream["tags"])) end)

    stream_tags |> Map.merge(tag_map(format["tags"])) |> MusicTags.from_raw()
  end

  defp music_tags(_format, _streams, _type), do: nil

  defp tag_map(tags) when is_map(tags) do
    tags
    |> Enum.filter(fn {key, _value} -> is_binary(key) and String.valid?(key) end)
    |> Map.new(fn {key, value} -> {String.downcase(key), value} end)
  end

  defp tag_map(_tags), do: %{}

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

  defp tracks(streams, content_type) do
    Enum.reduce_while(streams, {:ok, []}, fn stream, {:ok, acc} ->
      case track(stream, content_type) do
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

  defp track(%{"codec_type" => "video", "disposition" => %{"attached_pic" => 1}}, :music),
    do: {:ok, nil}

  defp track(stream, _content_type), do: track(stream)

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

defmodule Bolognesa.Playback.Infrastructure.TranscodeManager.HlsPlaylist do
  @moduledoc "Decide whether a session's sliding HLS playlist has enough published output to start."

  @ready_seconds 4

  @type status :: :ready | :waiting

  @doc """
  Ready means at least one segment, four published seconds (or a completed playlist),
  and every referenced segment file present. Returns the status, segment count and
  published milliseconds.
  """
  @spec read(Path.t()) :: {status(), non_neg_integer(), non_neg_integer()}
  def read(directory) do
    case File.read(Path.join(directory, "index.m3u8")) do
      {:ok, manifest} -> evaluate(directory, manifest)
      _ -> {:waiting, 0, 0}
    end
  end

  defp evaluate(directory, manifest) do
    segments = Regex.scan(~r/^seg-[0-9]{6,12}\.ts$/m, manifest) |> List.flatten()
    seconds = published_seconds(manifest)
    enough? = seconds >= @ready_seconds or String.contains?(manifest, "#EXT-X-ENDLIST")

    ready? =
      enough? and segments != [] and
        Enum.all?(segments, &File.regular?(Path.join(directory, &1)))

    {if(ready?, do: :ready, else: :waiting), length(segments), round(seconds * 1000)}
  end

  defp published_seconds(manifest) do
    ~r/^#EXTINF:(\d+(?:\.\d+)?),/m
    |> Regex.scan(manifest, capture: :all_but_first)
    |> Enum.reduce(0.0, fn [duration], total ->
      {seconds, ""} = Float.parse(duration)
      total + seconds
    end)
  end
end

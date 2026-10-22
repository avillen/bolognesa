defmodule Bolognesa.Playback.Domain.Policies.TranscodeStrategy do
  @moduledoc "Select the initial transcode strategy from current technical metadata."

  alias Bolognesa.Playback.Domain.ReadModels.Source

  @type t :: :direct | :audio_only | :full_transcode

  @spec choose(Source.t()) :: t()
  def choose(%Source{format: format, tracks: tracks}) do
    video = Enum.find(tracks, &(&1.kind == :video))
    audio = Enum.find(tracks, &(&1.kind == :audio))

    cond do
      format in ["matroska", "matroska,webm"] and codec(video) == "h264" and
          codec(audio) in ["ac3", "eac3"] ->
        :audio_only

      format == "avi" and codec(video) == "mpeg4" and codec(audio) in ["ac3", "eac3"] ->
        :full_transcode

      true ->
        :direct
    end
  end

  defp codec(nil), do: nil
  defp codec(track), do: track.codec
end

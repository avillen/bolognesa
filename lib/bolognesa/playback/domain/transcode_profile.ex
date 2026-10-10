defmodule Bolognesa.Playback.Domain.TranscodeProfile do
  @moduledoc "Select the initial delivery profile from current technical metadata."

  alias Bolognesa.Playback.Domain.Source

  @type t :: :direct | :audio | :video

  @spec choose(Source.t()) :: t()
  def choose(%Source{format: format, tracks: tracks}) do
    video = Enum.find(tracks, &(&1.kind == :video))
    audio = Enum.find(tracks, &(&1.kind == :audio))

    cond do
      format in ["matroska", "matroska,webm"] and codec(video) == "h264" and
          codec(audio) in ["ac3", "eac3"] ->
        :audio

      format == "avi" and codec(video) == "mpeg4" and codec(audio) in ["ac3", "eac3"] ->
        :video

      true ->
        :direct
    end
  end

  defp codec(nil), do: nil
  defp codec(track), do: track.codec
end

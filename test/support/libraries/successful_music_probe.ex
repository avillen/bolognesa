defmodule Bolognesa.Libraries.Support.SuccessfulMusicProbe do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Services.MediaProbe
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.{MusicTags, TechnicalMedia}
  @impl true
  def inspect(_library, _file),
    do:
      TechnicalMedia.new(%{
        format: "mp3",
        duration_ms: 2500,
        tracks: [%{kind: :audio, codec: "mp3"}],
        music_tags: MusicTags.from_raw(%{"title" => "Sample Song"})
      })
end

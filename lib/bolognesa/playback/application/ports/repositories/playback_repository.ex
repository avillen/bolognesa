defmodule Bolognesa.Playback.Application.Ports.Repositories.PlaybackRepository do
  @moduledoc "Read currently playable video sources and music track sources."

  @type adapter :: atom()
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef

  @callback find_video_source(content_ref :: ContentRef.t(), file_id :: pos_integer()) ::
              {:ok, Source.t()} | {:error, :not_found | :missing | :unavailable}
  @callback find_track_source(track_id :: pos_integer(), file_id :: pos_integer()) ::
              {:ok, Source.t()} | {:error, :not_found | :missing | :unavailable}
end

defmodule Bolognesa.Playback.Application.Ports.Repositories.PlaybackRepository do
  @moduledoc "Read currently playable video sources and music track sources."

  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef

  @type adapter :: module()
  @type source_result :: {:ok, Source.t()} | :not_found | {:error, :missing | :unavailable}

  @callback fetch_video_source(content_ref :: ContentRef.t(), file_id :: pos_integer()) ::
              source_result()
  @callback fetch_track_source(track_id :: pos_integer(), file_id :: pos_integer()) ::
              source_result()
end

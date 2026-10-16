defmodule Bolognesa.Playback.Application.Ports.Repositories.PlaybackRepository do
  @moduledoc "Read a confirmed movie-to-file association for playback."

  @type adapter :: atom()
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef

  @callback find_source(content_ref :: ContentRef.t(), file_id :: pos_integer()) ::
              {:ok, Source.t()} | {:error, :not_found | :missing | :unavailable}
  @callback find_track_source(track_id :: pos_integer(), file_id :: pos_integer()) ::
              {:ok, Source.t()} | {:error, :not_found | :missing | :unavailable}
end

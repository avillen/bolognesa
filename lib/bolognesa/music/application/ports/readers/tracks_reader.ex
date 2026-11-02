defmodule Bolognesa.Music.Application.Ports.Readers.TracksReader do
  @moduledoc "Bounded, library-scoped local music reads."
  alias Bolognesa.Music.Domain.ReadModels.TrackPage
  @type adapter :: atom()
  @callback fetch_track(track_id :: pos_integer()) ::
              {:ok, Bolognesa.Music.Domain.ReadModels.TrackRow.t()}
              | {:error, :not_found | :unavailable}
  @callback list_tracks(
              String.t(),
              pos_integer(),
              library_id :: pos_integer() | nil,
              user_id :: pos_integer()
            ) ::
              {:ok, TrackPage.t()} | {:error, :not_found | :unavailable}
  @callback list_album_tracks(
              album_id :: pos_integer(),
              String.t(),
              pos_integer(),
              library_id :: pos_integer() | nil,
              limit :: 50 | 501,
              user_id :: pos_integer()
            ) :: {:ok, TrackPage.t()} | {:error, :not_found | :unavailable}
end

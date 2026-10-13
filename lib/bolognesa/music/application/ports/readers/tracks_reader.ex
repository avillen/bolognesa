defmodule Bolognesa.Music.Application.Ports.Readers.TracksReader do
  @moduledoc "Bounded, library-scoped local music reads."
  alias Bolognesa.Music.Domain.ReadModels.TrackPage
  @type adapter :: atom()
  @callback list_tracks(String.t(), pos_integer(), library_id :: pos_integer() | nil) ::
              {:ok, TrackPage.t()} | {:error, :not_found | :unavailable}
end

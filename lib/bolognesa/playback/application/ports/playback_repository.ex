defmodule Bolognesa.Playback.Application.Ports.PlaybackRepository do
  @moduledoc "Read a confirmed movie-to-file association for playback."

  @type adapter :: atom()
  alias Bolognesa.Playback.Domain.Source

  @callback find_source(catalog_entry_id :: pos_integer(), file_id :: pos_integer()) ::
              {:ok, Source.t()} | {:error, :not_found | :missing | :unavailable}
end

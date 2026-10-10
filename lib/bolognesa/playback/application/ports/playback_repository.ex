defmodule Bolognesa.Playback.Application.Ports.PlaybackRepository do
  @moduledoc "Read a confirmed movie-to-file association for playback."

  @type adapter :: atom()
  @type source :: %{
          path: binary(),
          relative_path: binary(),
          size_bytes: non_neg_integer(),
          modified_at: DateTime.t()
        }

  @callback find_source(pos_integer(), pos_integer()) ::
              {:ok, source()} | {:error, :not_found | :missing | :unavailable}
end

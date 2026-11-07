defmodule Bolognesa.Playback.Domain.ValueObjects.MediaConfiguration do
  @moduledoc "Normalized elementary-stream facts used for one exact browser probe."
  @type video :: %{
          codec_string: String.t(),
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          frame_rate: float() | nil,
          bit_rate: pos_integer() | nil
        }
  @type audio :: %{
          codec_string: String.t(),
          sample_rate: pos_integer() | nil,
          channels: pos_integer() | nil,
          bit_rate: pos_integer() | nil
        }
  @type t :: %__MODULE__{
          container: :mp4 | :webm | :matroska | :mpegts,
          mime: String.t(),
          video: video(),
          audio: audio() | nil
        }
  @enforce_keys [:container, :mime, :video, :audio]
  defstruct [:container, :mime, :video, :audio]
end

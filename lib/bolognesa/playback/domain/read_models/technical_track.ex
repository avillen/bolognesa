defmodule Bolognesa.Playback.Domain.ReadModels.TechnicalTrack do
  @moduledoc "A playback-owned projection of an inspected track."

  @type t :: %__MODULE__{
          kind: :video | :audio | :subtitle,
          codec: String.t() | nil,
          codec_string: String.t() | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          channels: pos_integer() | nil,
          language: String.t() | nil,
          index: non_neg_integer() | nil,
          profile: String.t() | nil,
          level: non_neg_integer() | nil,
          pixel_format: String.t() | nil,
          bit_depth: pos_integer() | nil,
          frame_rate: String.t() | nil,
          bit_rate: pos_integer() | nil,
          sample_rate: pos_integer() | nil,
          default?: boolean() | nil,
          attached_picture?: boolean() | nil,
          color_transfer: String.t() | nil,
          color_primaries: String.t() | nil,
          color_space: String.t() | nil
        }

  defstruct [
    :kind,
    :codec,
    :codec_string,
    :width,
    :height,
    :channels,
    :language,
    :index,
    :profile,
    :level,
    :pixel_format,
    :bit_depth,
    :frame_rate,
    :bit_rate,
    :sample_rate,
    :default?,
    :attached_picture?,
    :color_transfer,
    :color_primaries,
    :color_space
  ]
end

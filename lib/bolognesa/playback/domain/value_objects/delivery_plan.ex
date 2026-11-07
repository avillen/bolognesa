defmodule Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan do
  @moduledoc "Server-owned stream actions bound to a source revision and transport."
  alias Bolognesa.Playback.Domain.ValueObjects.MediaConfiguration
  @type mode :: :direct | :remux | :audio_conversion | :video_conversion | :full_conversion
  @type transport :: :file | :native_hls | :hls_js
  @type reason ::
          :original_supported
          | :remux_supported
          | :audio_conversion_required
          | :video_conversion_required
          | :full_conversion_required
  @type t :: %__MODULE__{
          revision: pos_integer(),
          video_index: non_neg_integer(),
          audio_index: non_neg_integer() | nil,
          mode: mode(),
          video_action: :original | :copy | :h264,
          audio_action: :original | :copy | :aac | :absent,
          configuration: MediaConfiguration.t(),
          transport: transport() | nil,
          reason: reason()
        }
  @enforce_keys [
    :revision,
    :video_index,
    :audio_index,
    :mode,
    :video_action,
    :audio_action,
    :configuration,
    :reason
  ]
  defstruct [
    :revision,
    :video_index,
    :audio_index,
    :mode,
    :video_action,
    :audio_action,
    :configuration,
    :transport,
    :reason
  ]
end

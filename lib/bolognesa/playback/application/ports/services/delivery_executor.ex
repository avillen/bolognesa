defmodule Bolognesa.Playback.Application.Ports.Services.DeliveryExecutor do
  @moduledoc "Validate physical delivery and start an authorized server-owned plan."
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan

  @type adapter :: module()
  @type error ::
          :source_inaccessible
          | :source_changed
          | :unsafe_entry
          | :unreadable
          | :unavailable
          | :busy
          | :invalid_offset
          | :tool_unavailable
          | :unsafe_root
          | :storage_unavailable
          | :unsupported
  @type result :: {:ok, :direct} | {:ok, :transcode, TranscodeSession.t()} | {:error, error()}
  @callback prepare(
              actor_id :: pos_integer(),
              ContentRef.t(),
              file_id :: pos_integer(),
              Source.t(),
              DeliveryPlan.t(),
              non_neg_integer(),
              TranscodeSession.stop_reason() | :session_replaced
            ) :: result()
end

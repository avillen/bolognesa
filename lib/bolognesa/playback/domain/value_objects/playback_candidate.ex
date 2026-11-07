defmodule Bolognesa.Playback.Domain.ValueObjects.PlaybackCandidate do
  @moduledoc "An issued exact configuration with a bounded candidate identifier."
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan

  @type t :: %__MODULE__{
          id: String.t(),
          plan: DeliveryPlan.t(),
          transports: [DeliveryPlan.transport()]
        }
  @enforce_keys [:id, :plan, :transports]
  defstruct [:id, :plan, :transports]
end

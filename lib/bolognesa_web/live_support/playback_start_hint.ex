defmodule BolognesaWeb.LiveSupport.PlaybackStartHint do
  @moduledoc """
  Separates the browser's optional checkpoint hint from its capability report.

  The hint is an untrusted `initial: %{position_ms, paused}` key beside the closed
  version-one report. It never names a file or attempt: those come from server state.
  An invalid hint is dropped; an oversized envelope is left whole so the report
  itself is rejected.
  """
  @max_envelope_bytes 8_192

  @type t :: %{position_ms: non_neg_integer(), paused: boolean()}

  @spec split(map(), non_neg_integer() | nil) :: {map(), t() | nil}
  def split(%{"initial" => initial} = raw, duration_ms) do
    if :erlang.external_size(raw) <= @max_envelope_bytes,
      do: {Map.delete(raw, "initial"), hint(initial, duration_ms)},
      else: {raw, nil}
  end

  def split(raw, _duration_ms), do: {raw, nil}

  defp hint(%{"position_ms" => position, "paused" => paused} = initial, duration_ms)
       when map_size(initial) == 2 and position in 0..2_147_483_647//1 and is_boolean(paused) do
    if is_nil(duration_ms) or position < duration_ms,
      do: %{position_ms: position, paused: paused}
  end

  defp hint(_initial, _duration_ms), do: nil
end

defmodule Bolognesa.Playback.Infrastructure.FfmpegProgress do
  @moduledoc "Retain only numeric fields from bounded FFmpeg progress lines."

  @type report :: %{
          optional(:ffmpeg_frame) => non_neg_integer(),
          optional(:ffmpeg_output_ms) => non_neg_integer(),
          optional(:ffmpeg_speed_milli) => non_neg_integer()
        }
  @type t :: %{discarding?: boolean(), pending: report()}

  @spec new() :: t()
  def new, do: %{discarding?: false, pending: %{}}

  # The port's line mode assembles fragmented writes and bounds each line to 1024 bytes.
  # Discard every fragment of an oversized line, including its final suffix.
  @spec consume(t(), {:eol | :noeol, binary()}) :: {t(), report() | nil}
  def consume(state, {:noeol, _bytes}), do: {%{state | discarding?: true}, nil}

  def consume(%{discarding?: true} = state, {:eol, _bytes}),
    do: {%{state | discarding?: false}, nil}

  def consume(state, {:eol, line}) do
    case :binary.split(line, "=") do
      ["progress", value] when value in ["continue", "end"] ->
        report = if map_size(state.pending) > 0, do: state.pending
        {%{state | pending: %{}}, report}

      ["frame", value] ->
        put_number(state, :ffmpeg_frame, value, 1)

      ["out_time_us", value] ->
        put_number(state, :ffmpeg_output_ms, value, 1000)

      ["speed", value] ->
        put_speed(state, String.trim(value))

      _ ->
        {state, nil}
    end
  end

  defp put_number(state, key, value, divisor) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 and number <= 9_007_199_254_740_991 ->
        {%{state | pending: Map.put(state.pending, key, div(number, divisor))}, nil}

      _ ->
        {state, nil}
    end
  end

  defp put_speed(state, value) do
    if Regex.match?(~r/\A[0-9]{1,6}(?:\.[0-9]{1,6})?(?:e[+-]?[0-9]{1,2})?x\z/, value) do
      case Float.parse(value) do
        {speed, "x"} when speed <= 1_000_000 ->
          {%{state | pending: Map.put(state.pending, :ffmpeg_speed_milli, round(speed * 1000))},
           nil}

        _ ->
          {state, nil}
      end
    else
      {state, nil}
    end
  end
end

defmodule Bolognesa.Playback.Infrastructure.TranscodeManager.Preparation do
  @moduledoc """
  Track one session's startup: published segments, readiness and FFmpeg progress.
  Each milestone (`first_progress`, `first_segment`, `ready`) is reported once.
  """
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession
  alias Bolognesa.Playback.Infrastructure.TranscodeManager.HlsPlaylist
  alias Bolognesa.Playback.Infrastructure.TranscodeManager.Preparation.FfmpegProgress
  alias Bolognesa.Playback.Infrastructure.TranscodeManager.Telemetry

  @type t :: %__MODULE__{
          session: TranscodeSession.t(),
          started_at: integer(),
          count: non_neg_integer(),
          published_ms: non_neg_integer(),
          first?: boolean(),
          ready?: boolean(),
          parser: FfmpegProgress.t(),
          progress: FfmpegProgress.report(),
          first_progress_ms: non_neg_integer() | nil,
          progress_at: integer() | nil
        }

  @enforce_keys [:session, :started_at, :parser]
  defstruct [
    :session,
    :started_at,
    :parser,
    count: 0,
    published_ms: 0,
    first?: false,
    ready?: false,
    progress: %{},
    first_progress_ms: nil,
    progress_at: nil
  ]

  @spec new(TranscodeSession.t(), integer()) :: t()
  def new(session, started_at),
    do: %__MODULE__{session: session, started_at: started_at, parser: FfmpegProgress.new()}

  @doc "Record the latest playlist observation and report newly reached milestones."
  @spec observe(t(), HlsPlaylist.status(), non_neg_integer(), non_neg_integer()) :: t()
  def observe(prep, status, count, published_ms) do
    prep = %{prep | count: count, published_ms: published_ms}

    prep =
      if count > 0 and not prep.first?,
        do: %{report(prep, :first_segment) | first?: true},
        else: prep

    if status == :ready and not prep.ready?,
      do: %{report(prep, :ready) | ready?: true},
      else: prep
  end

  @doc "Feed one FFmpeg progress line from the port."
  @spec consume(t(), {:eol | :noeol, binary()}) :: t()
  def consume(prep, line) do
    {parser, report} = FfmpegProgress.consume(prep.parser, line)
    record_progress(%{prep | parser: parser}, report)
  end

  @spec timed_out(t()) :: t()
  def timed_out(prep), do: report(prep, :timeout)

  defp record_progress(prep, nil), do: prep

  defp record_progress(prep, report) do
    received_at = now()
    first? = is_nil(prep.first_progress_ms)

    prep = %{
      prep
      | progress: report,
        progress_at: received_at,
        first_progress_ms: prep.first_progress_ms || received_at - prep.started_at
    }

    if first?, do: report(prep, :first_progress), else: prep
  end

  defp report(prep, stage) do
    Telemetry.emit(:preparation, prep.session, measurements(prep), %{stage: stage})
    prep
  end

  defp measurements(prep) do
    base = %{
      duration_ms: now() - prep.started_at,
      segment_count: prep.count,
      published_ms: prep.published_ms
    }

    if prep.progress_at do
      base
      |> Map.merge(prep.progress)
      |> Map.merge(%{
        first_progress_ms: prep.first_progress_ms,
        progress_age_ms: now() - prep.progress_at
      })
    else
      base
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end

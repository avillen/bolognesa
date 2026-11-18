defmodule BolognesaWeb.LiveSupport.PlaybackAttempt do
  @moduledoc """
  One browser's try at playing a video file, from version selection until it is
  ready, fails, or ends (see `GLOSSARY.md`).

  Transitions are pure: they return the next attempt and the effects the caller
  must perform. An effect that produces a result is handed back to `resolve/4`
  together with that result. Events that do not belong to the current attempt
  return it unchanged with no effects.
  """
  alias Bolognesa.Playback
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan
  alias Bolognesa.Playback.Domain.ValueObjects.PlaybackCandidate
  alias BolognesaWeb.Params
  alias Ecto.UUID

  @typedoc "Why preparing the attempt failed, as reported by playback or the inspection refresh."
  @type failure_reason ::
          Playback.negotiation_reason()
          | Playback.transcode_reason()
          | :source_changed
          | :refresh_limited
          | :detection_unknown
  @typedoc "A visible failure: preparation was refused, or the conversion failed or was interrupted."
  @type error :: {:preparation, failure_reason()} | {:transcode, :preparation | :interrupted}
  @typedoc "The capability probe sent to the browser for the issued candidates."
  @type probe :: %{generation: String.t(), candidates: [map()]}
  @typedoc "Untrusted capability report as the browser sent it."
  @type raw_report :: map()
  @typedoc "Whether a delivery keeps the default autoplay or sets the browser's play state."
  @type autoplay :: :keep | boolean()
  @typedoc "Why a plan is selected: the browser's request, the compatible check, or a recovery at an offset."
  @type plan_purpose ::
          :requested | {:compatible_check, DeliveryPlan.t()} | {:recovery, non_neg_integer()}
  @typedoc "Work the caller performs; those producing a result are answered through `resolve/4`."
  @type effect ::
          {:load_candidates, pos_integer()}
          | {:schedule_capability_timeout, String.t(), pos_integer()}
          | {:select_plan, plan_purpose(), pos_integer(), [PlaybackCandidate.t()], raw_report()}
          | {:deliver, pos_integer(), DeliveryPlan.t() | nil, non_neg_integer(),
             TranscodeSession.stop_reason() | :session_replaced, autoplay()}
          | {:schedule_poll, String.t(), pos_integer()}
          | {:fetch_status, String.t()}
          | {:stop_session, String.t(), TranscodeSession.stop_reason()}
          | {:prepare_original, pos_integer()}
          | {:refresh_inspection, pos_integer()}
          | {:resume_session, String.t(), non_neg_integer() | nil}
  @typedoc "The result of performing an effect, as returned by the playback facade."
  @type result ::
          {:ok, Source.t(), [PlaybackCandidate.t()]}
          | {:ok, DeliveryPlan.t()}
          | {:ok, :direct}
          | {:ok, :transcode, TranscodeSession.t()}
          | :ok
          | :ready
          | :waiting
          | :not_found
          | {:error, failure_reason()}
  @typedoc "One browser's playback attempt."
  @type t :: %__MODULE__{
          id: String.t() | nil,
          phase: :idle | :checking | :preparing | :ready | :error,
          file_id: pos_integer() | nil,
          duration_ms: non_neg_integer() | nil,
          probe: probe() | nil,
          candidates: [PlaybackCandidate.t()],
          plan: DeliveryPlan.t() | nil,
          report: raw_report() | nil,
          compatible_available?: boolean(),
          recovery_used?: boolean(),
          session: TranscodeSession.t() | nil,
          stream_ready?: boolean(),
          stream_paused?: boolean(),
          stream_autoplay?: boolean(),
          deadline: integer() | nil,
          error: error() | nil,
          refresh_used?: boolean(),
          refresh_requested?: boolean()
        }

  defstruct id: nil,
            phase: :idle,
            file_id: nil,
            duration_ms: nil,
            probe: nil,
            candidates: [],
            plan: nil,
            report: nil,
            compatible_available?: false,
            recovery_used?: false,
            session: nil,
            stream_ready?: false,
            stream_paused?: false,
            stream_autoplay?: false,
            deadline: nil,
            error: nil,
            refresh_used?: false,
            refresh_requested?: false

  @capability_timeout_ms 5_000
  @preparation_ms 60_000

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Starts a new attempt for an available file, with its single recovery."
  @spec select(t(), pos_integer()) :: {t(), [effect()]}
  def select(attempt, file_id) do
    next = %{direct(new(), file_id) | id: UUID.generate()}
    {next, stop(attempt, :version_selected) ++ [{:load_candidates, file_id}]}
  end

  @doc "Accepts the browser's capability report for the current probe."
  @spec report(t(), map()) :: {t(), [effect()]}
  def report(
        %{phase: :checking, probe: %{generation: generation}} = attempt,
        %{"generation" => generation} = raw
      ),
      do: {attempt, [select_plan(attempt, :requested, raw)]}

  def report(attempt, _raw), do: {attempt, []}

  @doc "Redelivers the displayed stream from a new offset, keeping the browser's play state."
  @spec seek(t(), map()) :: {t(), [effect()]}
  def seek(
        %{phase: :ready, session: %{id: id} = session} = attempt,
        %{"session_id" => id, "position_ms" => position} = params
      ) do
    case offset(position, session.duration_ms) do
      nil -> {attempt, []}
      offset -> {attempt, [deliver(attempt, offset, :seek, params["playing"] == "true")]}
    end
  end

  def seek(attempt, _params), do: {attempt, []}

  @doc """
  Handles a browser playback failure of the direct file (`:file`) or the
  displayed stream (`:session`). A media failure recovers once to a compatible
  plan; network, aborted and unknown failures interrupt playback.
  """
  @spec client_failed(t(), :file | :session, map()) :: {t(), [effect()]}
  def client_failed(attempt, source, params) do
    with true <- displays?(attempt, {source, params["#{source}_id"]}),
         %{phase: :ready, id: id} when is_binary(id) <- attempt,
         ^id <- params["attempt_id"],
         offset when is_integer(offset) <- offset(params["position_ms"], attempt.duration_ms) do
      case params["error_kind"] do
        "media" -> recover(attempt, offset)
        kind when kind in ["network", "aborted", "unknown"] -> interrupted(attempt)
        _ -> {attempt, []}
      end
    else
      _ -> {attempt, []}
    end
  end

  @doc "Starts a new attempt on the compatible plan the browser was offered."
  @spec play_compatible(t()) :: {t(), [effect()]}
  def play_compatible(%{compatible_available?: true, phase: phase} = attempt)
      when phase in [:ready, :error],
      do: recover(%{attempt | id: UUID.generate(), recovery_used?: false}, 0)

  def play_compatible(attempt), do: {attempt, []}

  @spec play_original(t()) :: {t(), [effect()]}
  def play_original(%{file_id: nil} = attempt), do: {attempt, []}
  def play_original(attempt), do: {attempt, [{:prepare_original, attempt.file_id}]}

  @doc "Requests one technical inspection refresh for the selected file."
  @spec refresh(t()) :: {t(), [effect()]}
  def refresh(%{file_id: file_id, refresh_used?: false} = attempt) when not is_nil(file_id),
    do: {%{attempt | refresh_used?: true}, [{:refresh_inspection, file_id}]}

  def refresh(attempt), do: {attempt, []}

  @spec pause(t(), String.t()) :: {t(), [effect()]}
  def pause(%{session: %{id: id}} = attempt, id), do: {%{attempt | stream_paused?: true}, []}
  def pause(attempt, _id), do: {attempt, []}

  @spec resume(t(), map()) :: {t(), [effect()]}
  def resume(%{phase: :ready, session: %{id: id} = session} = attempt, %{
        "session_id" => id,
        "position_ms" => position
      }),
      do: {attempt, [{:resume_session, id, offset(position, session.duration_ms)}]}

  def resume(attempt, _params), do: {attempt, []}

  @spec ended(t(), map()) :: {t(), [effect()]}
  def ended(%{session: %{id: id}} = attempt, %{"session_id" => id}),
    do: {%{attempt | stream_paused?: true}, stop(attempt, :ended)}

  def ended(attempt, _params), do: {attempt, []}

  @doc "Starts over with no selected file, stopping any displayed session."
  @spec reset(t()) :: {t(), [effect()]}
  def reset(attempt), do: {new(), stop(attempt, :version_selected)}

  @doc "Whether a browser event refers to the playback in progress."
  @spec playing?(t(), map()) :: boolean()
  def playing?(attempt, %{"session_id" => id}), do: displays?(attempt, {:session, id})

  def playing?(%{phase: :ready, error: nil} = attempt, %{"file_id" => id}),
    do: displays?(attempt, {:file, id})

  def playing?(_attempt, _params), do: false

  @doc "Whether restoring `session_id` replaced it with a different, healthy stream."
  @spec restored?(t(), t(), String.t()) :: boolean()
  def restored?(%{session: %{id: id}}, %{session: %{id: next_id}, error: nil}, id),
    do: next_id != id

  def restored?(_before, _after, _session_id), do: false

  @doc "Handles a scheduled preparation poll for the session still preparing."
  @spec poll_due(t(), String.t()) :: {t(), [effect()]}
  def poll_due(%{phase: :preparing, stream_ready?: false, session: %{id: id}} = attempt, id),
    do: {attempt, [{:fetch_status, id}]}

  def poll_due(attempt, _id), do: {attempt, []}

  @spec capability_timed_out(t(), String.t()) :: {t(), [effect()]}
  def capability_timed_out(
        %{phase: :checking, probe: %{generation: generation}} = attempt,
        generation
      ),
      do: {preparation_failed(attempt, :detection_unknown), []}

  def capability_timed_out(attempt, _generation), do: {attempt, []}

  @doc "Applies the result of an effect this attempt emitted."
  @spec resolve(t(), effect(), result(), integer()) :: {t(), [effect()]}
  def resolve(attempt, {:load_candidates, _file_id}, {:ok, source, candidates}, _now_ms) do
    generation = UUID.generate()
    probe = %{generation: generation, candidates: Enum.map(candidates, &probe_candidate/1)}

    {%{
       attempt
       | duration_ms: source.duration_ms,
         phase: :checking,
         candidates: candidates,
         probe: probe
     }, [{:schedule_capability_timeout, generation, @capability_timeout_ms}]}
  end

  def resolve(attempt, {:load_candidates, _file_id}, {:error, reason}, _now_ms),
    do: {preparation_failed(attempt, reason), []}

  def resolve(attempt, {:select_plan, :requested, _, _, raw}, {:ok, plan}, _now_ms) do
    next = %{attempt | probe: nil, plan: plan, report: raw}

    {next,
     [
       select_plan(next, {:compatible_check, plan}, compatible(raw)),
       deliver(next, 0, :version_selected)
     ]}
  end

  def resolve(attempt, {:select_plan, :requested, _, _, _}, {:error, :invalid_report}, _now_ms),
    do: {attempt, []}

  def resolve(attempt, {:select_plan, :requested, _, _, _}, {:error, reason}, _now_ms),
    do: {preparation_failed(attempt, reason), []}

  def resolve(attempt, {:select_plan, {:compatible_check, selected}, _, _, _}, result, _now_ms),
    do:
      {%{attempt | compatible_available?: match?({:ok, plan} when plan != selected, result)}, []}

  def resolve(attempt, {:deliver, file_id, _, _, _, autoplay}, result, now_ms) do
    next =
      case result do
        {:ok, :direct} ->
          {direct(attempt, file_id), []}

        {:ok, :transcode, session} ->
          {preparing(attempt, session, now_ms), [{:schedule_poll, session.id, 250}]}

        {:error, reason} ->
          {preparation_failed(attempt, reason), []}
      end

    case {next, autoplay} do
      {next, :keep} -> next
      {{attempt, effects}, autoplay} -> {%{attempt | stream_autoplay?: autoplay}, effects}
    end
  end

  def resolve(attempt, {:fetch_status, _id}, :ready, _now_ms),
    do: {%{attempt | phase: :ready, stream_ready?: true, stream_paused?: true}, []}

  def resolve(attempt, {:fetch_status, id}, :waiting, now_ms) do
    if now_ms < attempt.deadline do
      {attempt, [{:schedule_poll, id, 500}]}
    else
      {transcode_failed(attempt, :preparation), stop(attempt, :preparation_timeout)}
    end
  end

  def resolve(attempt, {:fetch_status, _id}, _status, _now_ms),
    do: {transcode_failed(attempt, :preparation), []}

  def resolve(attempt, {:select_plan, {:recovery, offset}, _, _, _}, result, _now_ms) do
    stopped = stop(attempt, :client_error)

    case result do
      {:ok, plan} when plan.mode != :direct and plan != attempt.plan ->
        next = %{attempt | plan: plan}
        {next, stopped ++ [deliver(next, offset, :session_replaced)]}

      {:error, reason} ->
        {preparation_failed(attempt, reason), stopped}

      _ ->
        {preparation_failed(attempt, :unsupported), stopped}
    end
  end

  def resolve(attempt, {:prepare_original, file_id}, {:ok, :direct}, _now_ms) do
    next = %{
      direct(attempt, file_id)
      | id: UUID.generate(),
        report: nil,
        compatible_available?: false,
        recovery_used?: true,
        plan: nil
    }

    {next, stop(attempt, :version_selected)}
  end

  def resolve(attempt, {:prepare_original, _}, {:error, reason}, _now_ms),
    do: {preparation_failed(attempt, reason), []}

  def resolve(attempt, {:refresh_inspection, _}, :ok, _now_ms),
    do: {%{attempt | refresh_requested?: true}, []}

  def resolve(attempt, {:refresh_inspection, _}, {:error, reason}, _now_ms),
    do: {preparation_failed(attempt, reason), []}

  def resolve(attempt, {:resume_session, _, _}, :ok, _now_ms),
    do: {%{attempt | stream_paused?: false}, []}

  def resolve(attempt, {:resume_session, _, nil}, _result, _now_ms), do: {attempt, []}

  def resolve(attempt, {:resume_session, _, offset}, _result, _now_ms),
    do: {attempt, [deliver(attempt, offset, :session_replaced)]}

  # Whether a browser event names what is displayed: the stream's session, or the direct file.
  defp displays?(%{session: %{id: id}}, {:session, id}), do: true

  defp displays?(%{session: nil, file_id: file_id}, {:file, id}) when not is_nil(file_id),
    do: to_string(file_id) == id

  defp displays?(_attempt, _ref), do: false

  defp recover(%{report: report, recovery_used?: false} = attempt, offset) when is_map(report) do
    next = %{attempt | recovery_used?: true, compatible_available?: false}
    {next, [select_plan(next, {:recovery, offset}, compatible(report))]}
  end

  defp recover(attempt, _offset), do: interrupted(attempt)

  defp interrupted(attempt),
    do: {transcode_failed(attempt, :interrupted), stop(attempt, :client_error)}

  defp select_plan(attempt, purpose, raw),
    do: {:select_plan, purpose, attempt.file_id, attempt.candidates, raw}

  defp deliver(attempt, offset_ms, reason, autoplay \\ :keep),
    do: {:deliver, attempt.file_id, attempt.plan, offset_ms, reason, autoplay}

  defp compatible(raw), do: Map.put(raw, "preference", "compatible")

  defp direct(attempt, file_id), do: %{clear_delivery(attempt) | phase: :ready, file_id: file_id}

  defp clear_delivery(attempt) do
    %{
      attempt
      | session: nil,
        stream_ready?: false,
        stream_paused?: false,
        stream_autoplay?: false,
        error: nil
    }
  end

  defp preparing(attempt, session, now_ms) do
    %{
      clear_delivery(attempt)
      | file_id: session.file_id,
        phase: :preparing,
        deadline: now_ms + @preparation_ms,
        session: session,
        stream_autoplay?: true
    }
  end

  defp preparation_failed(attempt, reason), do: fail(attempt, {:preparation, reason})

  defp transcode_failed(attempt, stage), do: fail(attempt, {:transcode, stage})

  # Offsets are whole-file milliseconds within the media duration when it is known.
  defp offset(value, duration_ms) do
    offset = Params.integer(value, 0..2_147_483_647)
    if offset && (is_nil(duration_ms) or offset <= duration_ms), do: offset
  end

  defp fail(attempt, error), do: %{attempt | phase: :error, probe: nil, error: error}

  defp stop(%{session: nil}, _reason), do: []
  defp stop(%{session: session}, reason), do: [{:stop_session, session.id, reason}]

  defp probe_candidate(candidate) do
    config = candidate.plan.configuration

    %{
      id: candidate.id,
      transports: candidate.transports,
      configuration: %{mime: config.mime, video: config.video, audio: config.audio}
    }
  end
end

defmodule Bolognesa.Libraries.Domain.Entities.Scan do
  @moduledoc "Persisted scan progress and lifecycle rules independent of its job executor."

  alias Bolognesa.Libraries.Domain.Entities.Library

  @reasons [
    :source_inaccessible,
    :source_outside_roots,
    :source_changed,
    :entry_unreadable,
    :unsafe_entry,
    :storage_unavailable,
    :timeout,
    :attempts_exhausted,
    :unexpected_failure
  ]

  @type id :: pos_integer()
  @type generation :: String.t()
  @type state :: :queued | :running | :retrying | :completed | :failed
  @type reason ::
          :source_inaccessible
          | :source_outside_roots
          | :source_changed
          | :entry_unreadable
          | :unsafe_entry
          | :storage_unavailable
          | :timeout
          | :attempts_exhausted
          | :unexpected_failure
  @type t :: %__MODULE__{
          id: id(),
          library_id: Library.id(),
          job_id: pos_integer(),
          state: state(),
          force_inspection?: boolean(),
          generation: generation() | nil,
          attempt: non_neg_integer(),
          files_discovered: non_neg_integer(),
          failure_reason: reason() | nil,
          requested_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          attempt_started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil,
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :library_id,
    :job_id,
    :generation,
    :failure_reason,
    :requested_at,
    :started_at,
    :attempt_started_at,
    :finished_at,
    :updated_at,
    state: :queued,
    force_inspection?: false,
    attempt: 0,
    files_discovered: 0
  ]

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{state: state}), do: state in [:queued, :running, :retrying]

  @doc "Applies a lifecycle transition; repeating a terminal state preserves every field."
  @spec transition(t(), state(), reason() | nil, DateTime.t()) ::
          {:ok, t()} | {:error, :invalid_transition}
  def transition(%__MODULE__{state: state} = scan, state, _reason, _now)
      when state in [:completed, :failed],
      do: {:ok, scan}

  def transition(%__MODULE__{} = scan, state, reason, %DateTime{} = now) do
    if allowed_transition?(scan.state, state) and valid_reason?(state, reason) do
      {:ok, apply_transition(scan, state, reason, now)}
    else
      {:error, :invalid_transition}
    end
  end

  def transition(%__MODULE__{}, _state, _reason, _now), do: {:error, :invalid_transition}

  defp allowed_transition?(:queued, state), do: state in [:running, :retrying, :failed]

  defp allowed_transition?(:running, state),
    do: state in [:running, :retrying, :completed, :failed]

  defp allowed_transition?(:retrying, state), do: state in [:running, :failed]
  defp allowed_transition?(_from, _to), do: false

  defp valid_reason?(state, nil) when state in [:running, :completed], do: true
  defp valid_reason?(state, reason) when state in [:retrying, :failed], do: reason in @reasons
  defp valid_reason?(_state, _reason), do: false

  defp apply_transition(scan, :running, nil, now) do
    %{
      scan
      | state: :running,
        started_at: scan.started_at || now,
        attempt_started_at: now,
        failure_reason: nil,
        finished_at: nil,
        updated_at: now
    }
  end

  defp apply_transition(scan, state, reason, now) do
    %{
      scan
      | state: state,
        failure_reason: reason,
        finished_at: finish_time(state, now),
        updated_at: now
    }
  end

  defp finish_time(state, now) when state in [:completed, :failed], do: now
  defp finish_time(:retrying, _now), do: nil
end

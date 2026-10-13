defmodule Bolognesa.Music.Domain.Entities.ImportState do
  @moduledoc "Local musical import state."
  defstruct [
    :media_file_id,
    :observed_revision,
    :inspection_token,
    :state,
    :job_id,
    :failure_reason,
    :started_at,
    :finished_at
  ]

  @type t :: %__MODULE__{
          media_file_id: pos_integer(),
          observed_revision: pos_integer(),
          inspection_token: String.t(),
          state: :pending | :running | :succeeded | :failed,
          job_id: pos_integer() | nil,
          failure_reason: :storage_unavailable | :attempts_exhausted | :unexpected_failure | nil,
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil
        }
end

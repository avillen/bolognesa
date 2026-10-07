defmodule Bolognesa.Identification.Domain.Identification do
  @moduledoc "The current identification decision for one physical media file."

  defstruct [
    :media_file_id,
    :movie_id,
    :state,
    :origin,
    :observed_revision,
    :token,
    :needs_review?,
    :failure_reason,
    :candidate_data,
    :job_id,
    :started_at,
    :finished_at
  ]

  @type state :: :pending | :automatic | :manual | :manual_unidentified | :failed | :unmatched
  @type origin :: :automatic | :manual | nil
  @type t :: %__MODULE__{
          media_file_id: pos_integer(),
          movie_id: pos_integer() | nil,
          state: state(),
          origin: origin(),
          observed_revision: pos_integer(),
          token: Ecto.UUID.t(),
          needs_review?: boolean(),
          failure_reason: atom() | nil,
          candidate_data: map(),
          job_id: pos_integer() | nil,
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil
        }

  @spec request(t() | nil, pos_integer(), Ecto.UUID.t()) ::
          {:ok, t()} | {:error, :manual_locked | :invalid_request}
  def request(%__MODULE__{origin: :manual}, _revision, _token), do: {:error, :manual_locked}

  def request(existing, revision, token)
      when is_integer(revision) and revision > 0 and is_binary(token) do
    base = existing || %__MODULE__{}

    {:ok,
     %{
       base
       | state: :pending,
         observed_revision: revision,
         token: token,
         needs_review?: false,
         failure_reason: nil,
         job_id: nil,
         started_at: nil,
         finished_at: nil
     }}
  end

  def request(_existing, _revision, _token), do: {:error, :invalid_request}
end

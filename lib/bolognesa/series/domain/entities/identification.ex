defmodule Bolognesa.Series.Domain.Entities.Identification do
  @moduledoc "The current identification decision for one physical media file."

  @type state :: :pending | :automatic | :manual | :manual_unidentified | :failed | :unmatched
  @type origin :: :automatic | :manual | nil
  @type token :: String.t()
  @type candidate_data :: %{items: [map()]} | %{String.t() => [map()]}
  @type result :: %{
          candidate_data: candidate_data(),
          needs_review?: boolean(),
          failure_reason: binary() | nil
        }
  @type t :: %__MODULE__{
          media_file_id: pos_integer(),
          episode_ids: [pos_integer()],
          state: state(),
          origin: origin(),
          observed_revision: pos_integer(),
          token: token(),
          needs_review?: boolean(),
          failure_reason: binary() | nil,
          candidate_data: candidate_data(),
          job_id: pos_integer() | nil,
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil
        }

  defstruct [
    :media_file_id,
    :state,
    :origin,
    :observed_revision,
    :token,
    :needs_review?,
    :failure_reason,
    :candidate_data,
    :job_id,
    :started_at,
    :finished_at,
    episode_ids: []
  ]

  @spec new(pos_integer(), pos_integer(), token()) :: {:ok, t()} | {:error, :invalid_request}
  def new(file_id, revision, token)
      when is_integer(file_id) and file_id > 0 and is_integer(revision) and revision > 0 and
             is_binary(token) and byte_size(token) > 0 do
    {:ok,
     %__MODULE__{
       media_file_id: file_id,
       state: :pending,
       observed_revision: revision,
       token: token,
       needs_review?: false,
       candidate_data: %{items: []}
     }}
  end

  def new(_file_id, _revision, _token), do: {:error, :invalid_request}

  @spec request(t() | nil, pos_integer(), token()) ::
          {:ok, t()} | {:error, :manual_locked | :invalid_request}
  def request(%__MODULE__{origin: :manual}, _revision, _token), do: {:error, :manual_locked}

  def request(existing, revision, token)
      when is_integer(revision) and revision > 0 and is_binary(token) and byte_size(token) > 0 do
    base = existing || %__MODULE__{}

    {:ok,
     %{
       base
       | state: :pending,
         episode_ids: [],
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

  @spec start(t(), pos_integer() | nil, DateTime.t()) ::
          {:ok, t()} | {:error, :invalid_transition}
  def start(%__MODULE__{state: :pending, origin: origin} = decision, job_id, %DateTime{} = now)
      when origin != :manual and (is_nil(job_id) or (is_integer(job_id) and job_id > 0)) do
    {:ok, %{decision | started_at: now, job_id: job_id || decision.job_id}}
  end

  def start(_decision, _job_id, _now), do: {:error, :invalid_transition}

  @spec complete(t(), [pos_integer()], result(), DateTime.t()) ::
          {:ok, t()} | {:error, :invalid_transition | :invalid_result}
  def complete(%__MODULE__{state: :pending, origin: origin} = decision, ids, result, now)
      when origin != :manual do
    if valid_ids?(ids) and valid_result?(result) and is_struct(now, DateTime) do
      {:ok,
       %{
         decision
         | state: automatic_state(ids),
           origin: :automatic,
           episode_ids: ids,
           candidate_data: result.candidate_data,
           needs_review?: result.needs_review?,
           failure_reason: result.failure_reason,
           finished_at: now
       }}
    else
      {:error, :invalid_result}
    end
  end

  def complete(_decision, _ids, _result, _now), do: {:error, :invalid_transition}

  @spec fail(t(), binary(), DateTime.t()) :: {:ok, t()} | {:error, :invalid_transition}
  def fail(%__MODULE__{state: :pending, origin: origin} = decision, reason, %DateTime{} = now)
      when origin != :manual and is_binary(reason) and byte_size(reason) > 0 do
    {:ok,
     %{decision | state: :failed, failure_reason: reason, needs_review?: true, finished_at: now}}
  end

  def fail(_decision, _reason, _now), do: {:error, :invalid_transition}

  @spec correct(t(), pos_integer(), token(), [pos_integer()], DateTime.t()) ::
          {:ok, t()} | {:error, :invalid_correction}
  def correct(%__MODULE__{} = decision, revision, token, ids, %DateTime{} = now)
      when is_integer(revision) and revision > 0 and is_binary(token) and byte_size(token) > 0 do
    if valid_ids?(ids) do
      {:ok,
       %{
         decision
         | state: manual_state(ids),
           origin: :manual,
           observed_revision: revision,
           token: token,
           episode_ids: ids,
           needs_review?: false,
           failure_reason: nil,
           candidate_data: %{"items" => []},
           job_id: nil,
           started_at: nil,
           finished_at: now
       }}
    else
      {:error, :invalid_correction}
    end
  end

  def correct(_decision, _revision, _token, _ids, _now), do: {:error, :invalid_correction}

  defp automatic_state([]), do: :unmatched
  defp automatic_state(_ids), do: :automatic
  defp manual_state([]), do: :manual_unidentified
  defp manual_state(_ids), do: :manual

  defp valid_ids?(ids) when is_list(ids),
    do:
      length(ids) <= 100 and Enum.all?(ids, &(is_integer(&1) and &1 > 0)) and
        Enum.uniq(ids) == ids

  defp valid_ids?(_ids), do: false

  defp valid_result?(%{
         candidate_data: candidates,
         needs_review?: review,
         failure_reason: reason
       }),
       do:
         valid_candidates?(candidates) and is_boolean(review) and
           (is_nil(reason) or is_binary(reason))

  defp valid_result?(_result), do: false

  defp valid_candidates?(%{items: items}) when is_list(items), do: Enum.all?(items, &is_map/1)
  defp valid_candidates?(%{"items" => items}) when is_list(items), do: Enum.all?(items, &is_map/1)
  defp valid_candidates?(_candidates), do: false
end

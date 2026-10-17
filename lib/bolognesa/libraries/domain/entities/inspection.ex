defmodule Bolognesa.Libraries.Domain.Entities.Inspection do
  @moduledoc "Rules for requesting and recording technical media inspection."
  alias Bolognesa.Libraries.Domain.Entities.MediaFile
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.{MusicTags, TechnicalTrack}

  @type reason ::
          :source_changed
          | :source_inaccessible
          | :unsafe_entry
          | :unreadable
          | :unsupported
          | :timeout
          | :tool_unavailable
          | :invalid_output
          | :storage_unavailable
          | :attempts_exhausted
          | :unexpected_failure

  @type state :: :pending | :running | :succeeded | :failed

  @type t :: %__MODULE__{
          media_file_id: MediaFile.id(),
          token: String.t(),
          observed_revision: pos_integer(),
          state: state(),
          failure_reason: reason() | nil,
          job_id: pos_integer() | nil,
          format: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          music_tags: MusicTags.t() | nil,
          tracks: [TechnicalTrack.t()]
        }

  defstruct [
    :media_file_id,
    :token,
    :observed_revision,
    :failure_reason,
    :job_id,
    :format,
    :duration_ms,
    :music_tags,
    tracks: [],
    state: :pending
  ]

  @spec max_attempts() :: pos_integer()
  def max_attempts, do: 3

  @spec request?(MediaFile.t() | nil, boolean(), NewMediaFile.t(), boolean()) :: boolean()
  def request?(nil, _has_inspection?, _entry, _force?), do: true

  def request?(%MediaFile{availability: :missing}, _has_inspection?, _entry, _force?),
    do: true

  def request?(_file, false, _entry, _force?), do: true
  def request?(_file, _has_inspection?, _entry, true), do: true

  def request?(file, true, entry, false),
    do: MediaFile.revision_for(file, entry) != file.revision
end

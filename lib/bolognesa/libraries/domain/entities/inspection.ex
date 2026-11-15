defmodule Bolognesa.Libraries.Domain.Entities.Inspection do
  @moduledoc "Rules for requesting and recording technical media inspection."
  alias Bolognesa.Libraries.Domain.Entities.MediaFile
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile

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

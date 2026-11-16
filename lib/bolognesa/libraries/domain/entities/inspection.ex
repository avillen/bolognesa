defmodule Bolognesa.Libraries.Domain.Entities.Inspection do
  @moduledoc "Rules for requesting and recording technical media inspection."
  alias Bolognesa.Libraries.Domain.Entities.MediaFile

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

  @spec request?(
          MediaFile.t() | nil,
          has_inspection? :: boolean(),
          changed? :: boolean(),
          force? :: boolean()
        ) :: boolean()
  def request?(nil, _has_inspection?, _changed?, _force?), do: true

  def request?(%MediaFile{availability: :missing}, _has_inspection?, _changed?, _force?),
    do: true

  def request?(_file, has_inspection?, changed?, force?),
    do: not has_inspection? or force? or changed?
end

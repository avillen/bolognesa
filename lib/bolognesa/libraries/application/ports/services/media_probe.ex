defmodule Bolognesa.Libraries.Application.Ports.Services.MediaProbe do
  @moduledoc "Reads bounded technical metadata from a physical media file."
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.Entities.MediaFile
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalMedia

  @type adapter :: module()
  @type reason ::
          :source_changed
          | :source_inaccessible
          | :unsafe_entry
          | :unreadable
          | :unsupported
          | :timeout
          | :tool_unavailable
          | :invalid_output

  @typedoc "Bounded source of an unreadable result, with no command output or path."
  @type failure_stage :: :ffprobe | :file_access
  @type diagnostic_result ::
          {:ok, TechnicalMedia.t()} | {:error, reason()} | {:error, :unreadable, failure_stage()}

  @callback inspect(Library.t(), MediaFile.t()) :: {:ok, TechnicalMedia.t()} | {:error, reason()}
  @callback inspect_with_diagnostics(Library.t(), MediaFile.t()) :: diagnostic_result()
  @optional_callbacks inspect_with_diagnostics: 2
end

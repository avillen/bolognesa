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

  @callback inspect(Library.t(), MediaFile.t()) :: {:ok, TechnicalMedia.t()} | {:error, reason()}
end

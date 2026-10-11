defmodule Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus do
  @moduledoc "A library's latest scan and last successful completion."
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.Entities.Scan

  defstruct [:library_id, :latest_scan, :last_completed_at]

  @type t :: %__MODULE__{
          library_id: Library.id(),
          latest_scan: Scan.t() | nil,
          last_completed_at: DateTime.t() | nil
        }
end

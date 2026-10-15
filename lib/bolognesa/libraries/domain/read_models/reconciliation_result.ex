defmodule Bolognesa.Libraries.Domain.ReadModels.ReconciliationResult do
  @moduledoc "Confirmed changes retained even when a later recovery transaction fails."

  alias Bolognesa.Libraries.Domain.Entities.Library

  @type t :: %__MODULE__{
          changed_library_ids: [Library.id()],
          error: nil | :unavailable
        }

  defstruct changed_library_ids: [], error: nil
end

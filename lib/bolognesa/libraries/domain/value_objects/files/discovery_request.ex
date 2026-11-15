defmodule Bolognesa.Libraries.Domain.ValueObjects.Files.DiscoveryRequest do
  @moduledoc "Typed source and media policy for a read-only discovery walk."
  alias Bolognesa.Libraries.Domain.Entities.Library

  @type t :: %__MODULE__{
          path: String.t(),
          content_type: Library.content_type()
        }

  defstruct [:path, :content_type]

  # Persisted libraries are validated on creation; an error here would have no Scan reason.
  @spec new(Library.t()) :: {:ok, t()}
  def new(%Library{path: path, content_type: type}) do
    {:ok, %__MODULE__{path: path, content_type: type}}
  end
end

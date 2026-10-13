defmodule Bolognesa.Libraries.Domain.ValueObjects.Files.DiscoveryRequest do
  @moduledoc "Typed source and media policy for a read-only discovery walk."
  alias Bolognesa.Libraries.Domain.Entities.Library
  @enforce_keys [:path, :content_type]
  defstruct [:path, :content_type]
  @type t :: %__MODULE__{path: String.t(), content_type: Library.content_type()}
  @type error :: :invalid_request
  @spec new(Library.t()) :: {:ok, t()} | {:error, error()}
  def new(%Library{path: path, content_type: type})
      when is_binary(path) and byte_size(path) > 0 and type in [:movie, :series] do
    {:ok, %__MODULE__{path: path, content_type: type}}
  end

  def new(_library), do: {:error, :invalid_request}
end

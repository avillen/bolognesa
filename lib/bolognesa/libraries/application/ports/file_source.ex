defmodule Bolognesa.Libraries.Application.Ports.FileSource do
  @moduledoc "Validate an existing readable folder under an allowed physical root."
  @type adapter :: atom()
  @callback canonical_directory(String.t()) ::
              {:ok, String.t()} | {:error, :source_inaccessible | :source_outside_roots}
end

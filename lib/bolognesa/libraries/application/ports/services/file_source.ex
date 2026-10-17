defmodule Bolognesa.Libraries.Application.Ports.Services.FileSource do
  @moduledoc "Validate an existing readable folder under an allowed physical root."
  @type adapter :: module()
  @callback canonical_directory(String.t()) ::
              {:ok, String.t()} | {:error, :source_inaccessible | :source_outside_roots}
end

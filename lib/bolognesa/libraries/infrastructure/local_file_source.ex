defmodule Bolognesa.Libraries.Infrastructure.LocalFileSource do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.FileSource

  alias Bolognesa.Libraries.Infrastructure.LocalSourcePath

  @impl true
  def canonical_directory(path), do: LocalSourcePath.canonical_directory(path)
end

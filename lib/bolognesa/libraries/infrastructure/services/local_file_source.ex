defmodule Bolognesa.Libraries.Infrastructure.Services.LocalFileSource do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Services.FileSource

  alias Bolognesa.Infrastructure.LocalSourcePath

  @impl true
  def canonical_directory(path), do: LocalSourcePath.canonical_directory(path)
end

defmodule Bolognesa.Libraries.Support.SuccessfulMediaProbe do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Services.MediaProbe

  alias Bolognesa.Libraries.Domain.TechnicalMedia

  @impl true
  def inspect(_library, _file) do
    TechnicalMedia.new(%{
      format: "matroska",
      duration_ms: 2_500,
      tracks: [%{kind: :video, codec: "h264"}]
    })
  end
end

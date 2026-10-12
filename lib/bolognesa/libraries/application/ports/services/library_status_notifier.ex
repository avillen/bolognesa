defmodule Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier do
  @moduledoc "Signals confirmed library status changes. Adapters contain delivery failures."

  alias Bolognesa.Libraries.Domain.Entities.Library

  @type adapter :: module()
  @callback notify(Library.id()) :: :ok
end

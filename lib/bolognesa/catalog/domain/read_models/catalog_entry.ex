defmodule Bolognesa.Catalog.Domain.ReadModels.CatalogEntry do
  @moduledoc "Catalog identity and namespaced external reference."

  @type id :: pos_integer()
  @type t :: %__MODULE__{
          id: id(),
          kind: :movie | :series | :season | :episode,
          provider: :tmdb,
          resource_type: :movie | :series | :season | :episode,
          provider_id: pos_integer()
        }

  defstruct [:id, :kind, :provider, :resource_type, :provider_id]
end

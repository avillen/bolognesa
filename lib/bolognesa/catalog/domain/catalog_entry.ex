defmodule Bolognesa.Catalog.Domain.CatalogEntry do
  @moduledoc "Catalog identity and namespaced external reference."
  @enforce_keys [:id, :kind, :provider, :resource_type, :provider_id]
  defstruct [:id, :kind, :provider, :resource_type, :provider_id]

  @type id :: pos_integer()
  @type t :: %__MODULE__{
          id: id(),
          kind: :movie,
          provider: :tmdb,
          resource_type: :movie,
          provider_id: pos_integer()
        }
end

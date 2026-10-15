defmodule Bolognesa.Libraries.Domain.Entities.MediaFile do
  @moduledoc "A persisted physical file, identified by library and relative path bytes."
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.Entities.Scan
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile

  @type id :: pos_integer()
  @type availability :: :available | :missing
  @type t :: %__MODULE__{
          id: id(),
          library_id: Library.id(),
          relative_path: binary(),
          size_bytes: non_neg_integer(),
          modified_at: DateTime.t(),
          availability: availability(),
          revision: pos_integer(),
          last_seen_generation: Scan.generation()
        }

  defstruct [
    :id,
    :library_id,
    :relative_path,
    :size_bytes,
    :modified_at,
    :availability,
    :revision,
    :last_seen_generation
  ]

  @spec revision_for(t() | nil, NewMediaFile.t()) :: pos_integer()
  def revision_for(nil, _entry), do: 1

  def revision_for(file, entry) do
    changed? =
      file.size_bytes != entry.size_bytes or
        DateTime.compare(file.modified_at, entry.modified_at) != :eq

    if changed?, do: file.revision + 1, else: file.revision
  end
end

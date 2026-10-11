defmodule Bolognesa.Libraries.Application.InventoryRequestPlan do
  @moduledoc "Plans inventory revision and downstream requests for one observed file."
  alias Bolognesa.Libraries.Domain.Entities.Inspection
  alias Bolognesa.Libraries.Domain.Entities.MediaFile
  alias Bolognesa.Libraries.Domain.Entities.Scan
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile

  @type t :: %__MODULE__{
          revision: pos_integer(),
          new_discovery?: boolean(),
          inspect?: boolean(),
          identify?: boolean()
        }

  defstruct [:revision, :new_discovery?, :inspect?, :identify?]

  @spec for_entry(MediaFile.t() | nil, boolean(), NewMediaFile.t(), boolean(), Scan.generation()) ::
          t()
  def for_entry(previous, has_inspection?, entry, force_inspection?, generation) do
    revision = MediaFile.revision_for(previous, entry)
    changed? = previous != nil and revision != previous.revision
    new_discovery? = previous == nil or previous.last_seen_generation != generation

    inspect? =
      Inspection.request?(previous, has_inspection?, entry, force_inspection?) and
        (not force_inspection? or new_discovery? or changed?)

    identify? =
      previous == nil or previous.availability == :missing or changed?

    %__MODULE__{
      revision: revision,
      new_discovery?: new_discovery?,
      inspect?: inspect?,
      identify?: identify?
    }
  end
end

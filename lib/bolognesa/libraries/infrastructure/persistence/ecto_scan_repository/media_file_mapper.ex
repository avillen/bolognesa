defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileMapper do
  @moduledoc false
  alias Bolognesa.Libraries.Domain.MediaFile
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema

  @spec to_media_file(MediaFileSchema.t()) :: MediaFile.t()
  def to_media_file(schema) do
    %MediaFile{
      id: schema.id,
      library_id: schema.library_id,
      relative_path: schema.relative_path,
      size_bytes: schema.size_bytes,
      modified_at: schema.modified_at,
      availability: schema.availability,
      revision: schema.revision,
      last_seen_generation: schema.last_seen_generation
    }
  end
end

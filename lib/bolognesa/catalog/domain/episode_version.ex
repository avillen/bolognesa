defmodule Bolognesa.Catalog.Domain.EpisodeVersion do
  @moduledoc "Catalog-owned episode version read model."
  defstruct [
    :id,
    :availability,
    :size_bytes,
    :origin,
    :needs_review?,
    :episode_numbers,
    :format,
    :duration_ms,
    codecs: []
  ]

  @type id :: pos_integer()
  @type count :: non_neg_integer()
  @type t :: %__MODULE__{
          id: id(),
          availability: :available | :missing,
          size_bytes: non_neg_integer(),
          origin: :automatic | :manual,
          needs_review?: boolean(),
          episode_numbers: [pos_integer()],
          format: binary() | nil,
          duration_ms: non_neg_integer() | nil,
          codecs: [binary()]
        }
end

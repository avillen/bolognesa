defmodule Bolognesa.Music.Application.Ports.Readers.BrowseReader do
  @moduledoc "Library-scoped artist and album browsing."
  alias Bolognesa.Music.Domain.ReadModels.BrowsePage
  @type adapter :: atom()
  @type kind :: :artists | :albums
  @callback browse(
              kind(),
              artist_id :: pos_integer() | nil,
              String.t(),
              pos_integer(),
              library_id :: pos_integer() | nil
            ) :: {:ok, BrowsePage.t()} | {:error, :not_found | :unavailable}
end

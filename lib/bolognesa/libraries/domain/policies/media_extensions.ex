defmodule Bolognesa.Libraries.Domain.Policies.MediaExtensions do
  @moduledoc "Explicit discovery extensions by library content type."
  alias Bolognesa.Libraries.Domain.Entities.Library
  @video ~w(.mp4 .m4v .mkv .avi .mov .webm .mpeg .mpg .ts .m2ts)
  @spec for_type(Library.content_type()) :: [String.t()]
  def for_type(type) when type in [:movie, :series], do: @video
end

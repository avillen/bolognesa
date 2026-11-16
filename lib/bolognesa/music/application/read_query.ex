defmodule Bolognesa.Music.Application.ReadQuery do
  @moduledoc "Bounds shared by musical read queries: search text, page and identifiers."

  @spec valid?(term(), term(), term()) :: boolean()
  def valid?(text, page, library_id),
    do:
      is_binary(text) and byte_size(text) <= 256 and String.valid?(text) and
        is_integer(page) and page in 1..100_000 and valid_optional_id?(library_id)

  @spec valid_id?(term()) :: boolean()
  def valid_id?(id), do: is_integer(id) and id > 0

  @spec valid_optional_id?(term()) :: boolean()
  def valid_optional_id?(id), do: is_nil(id) or valid_id?(id)
end

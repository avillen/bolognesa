defmodule Bolognesa.ReadQuery do
  @moduledoc "Bounds shared by read queries: search text, page and identifiers."

  @spec valid?(term(), term(), term()) :: boolean()
  def valid?(text, page, library_id),
    do: valid_text?(text) and valid_page?(page) and valid_optional_id?(library_id)

  @spec valid_text?(term()) :: boolean()
  def valid_text?(text), do: is_binary(text) and byte_size(text) <= 256 and String.valid?(text)

  @spec valid_page?(term()) :: boolean()
  def valid_page?(page), do: is_integer(page) and page in 1..100_000

  @spec valid_id?(term()) :: boolean()
  def valid_id?(id), do: is_integer(id) and id > 0

  @spec valid_optional_id?(term()) :: boolean()
  def valid_optional_id?(id), do: is_nil(id) or valid_id?(id)
end

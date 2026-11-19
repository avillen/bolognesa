defmodule Bolognesa.ReadQuery do
  @moduledoc "Bounds shared by read queries: search text, page and identifiers."

  @type error :: {:error, :not_found | :invalid_query | :invalid_page}

  @spec validate(term(), term(), term()) :: :ok | error()
  def validate(text, page, library_id) do
    with :ok <- validate_text(text),
         :ok <- validate_page(page) do
      validate_optional_id(library_id)
    end
  end

  @spec validate_text(term()) :: :ok | {:error, :invalid_query}
  def validate_text(text) when is_binary(text) and byte_size(text) <= 256 do
    if String.valid?(text), do: :ok, else: {:error, :invalid_query}
  end

  def validate_text(_), do: {:error, :invalid_query}

  @spec validate_page(term()) :: :ok | {:error, :invalid_page}
  def validate_page(page) when is_integer(page) and page in 1..100_000, do: :ok
  def validate_page(_), do: {:error, :invalid_page}

  @spec validate_id(term()) :: :ok | {:error, :not_found}
  def validate_id(id) when is_integer(id) and id > 0, do: :ok
  def validate_id(_), do: {:error, :not_found}

  @spec validate_optional_id(term()) :: :ok | {:error, :invalid_query}
  def validate_optional_id(nil), do: :ok
  def validate_optional_id(id) when is_integer(id) and id > 0, do: :ok
  def validate_optional_id(_), do: {:error, :invalid_query}
end

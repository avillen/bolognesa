defmodule Bolognesa.Accounts.Domain.ValueObjects.Locale do
  @moduledoc "A user's language preference; nil follows the browser."
  @typedoc "Only nil, es and en are valid preferences."
  @type t :: String.t() | nil
  @spec validate(String.t() | nil) :: {:ok, t()} | {:error, :invalid_locale}
  def validate(value) when value in [nil, "es", "en"], do: {:ok, value}
  def validate(_value), do: {:error, :invalid_locale}
end

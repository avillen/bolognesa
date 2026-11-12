defmodule Bolognesa.Accounts.Domain.ValueObjects.Locale do
  @moduledoc "A user's language preference; nil follows the browser."
  @typedoc "A language preference; validation accepts only nil, es and en."
  @type t :: String.t() | nil

  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_locale}
  def validate(value) when value in [nil, "es", "en"], do: {:ok, value}
  def validate(_value), do: {:error, :invalid_locale}
end

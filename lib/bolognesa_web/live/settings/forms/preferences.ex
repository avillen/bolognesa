defmodule BolognesaWeb.Settings.Forms.Preferences do
  @moduledoc false
  import Ecto.Changeset
  alias Bolognesa.Identity.Domain.ValueObjects.Locale
  @spec changeset(Locale.t(), map()) :: Ecto.Changeset.t()
  def changeset(locale, params \\ %{}) do
    {%{locale: locale || ""}, %{locale: :string}}
    |> cast(params, [:locale], empty_values: [])
    |> validate_inclusion(:locale, ["", "es", "en"])
  end
end

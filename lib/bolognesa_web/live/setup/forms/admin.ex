defmodule BolognesaWeb.Setup.Forms.Admin do
  @moduledoc "Validation for the first administrator form."
  use Gettext, backend: BolognesaWeb.Gettext
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_confirmation, :string, virtual: true, redact: true
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:name, :email, :password, :password_confirmation])
    |> validate_required([:name, :email, :password, :password_confirmation])
    |> validate_length(:name, max: 120)
    |> validate_format(:email, ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
    |> validate_change(:password, fn :password, password ->
      if byte_size(password) in 12..72 and :binary.match(password, <<0>>) == :nomatch,
        do: [],
        else: [
          password:
            dgettext_noop(
              "errors",
              "debe tener entre 12 y 72 bytes y no contener caracteres nulos"
            )
        ]
    end)
    |> validate_confirmation(:password, required: true)
  end
end

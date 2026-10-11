defmodule BolognesaWeb.Library.Index.Forms.Library do
  @moduledoc "Web input for a library source."
  use Ecto.Schema
  use Gettext, backend: BolognesaWeb.Gettext
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :path, :string
    field :content_type, Ecto.Enum, values: [:movie, :series], default: :movie
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:name, :path, :content_type])
    |> validate_required([:name, :path, :content_type])
    |> validate_length(:name, max: 120)
    |> validate_length(:path, max: 4096)
    |> validate_change(:path, fn :path, path ->
      if Path.type(path) == :absolute,
        do: [],
        else: [path: dgettext_noop("errors", "debe ser una ruta absoluta")]
    end)
  end
end

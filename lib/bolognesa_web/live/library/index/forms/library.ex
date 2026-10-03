defmodule BolognesaWeb.Library.Index.Forms.Library do
  @moduledoc "Web input for a movie library source."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :path, :string
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:name, :path])
    |> validate_required([:name, :path])
    |> validate_length(:name, max: 120)
    |> validate_length(:path, max: 4096)
    |> validate_change(:path, fn :path, path ->
      if Path.type(path) == :absolute, do: [], else: [path: "debe ser una ruta absoluta"]
    end)
  end
end

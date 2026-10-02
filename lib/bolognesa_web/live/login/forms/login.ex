defmodule BolognesaWeb.Login.Forms.Login do
  @moduledoc "Input model for the browser login form."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :email, :string
    field :password, :string, virtual: true, redact: true
  end

  @spec changeset() :: Ecto.Changeset.t()
  def changeset do
    %__MODULE__{}
    |> change()
  end
end

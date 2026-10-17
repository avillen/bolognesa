defmodule Bolognesa.Libraries.Domain.ValueObjects.Files.NewLibrary do
  @moduledoc "Validated library details before storage."
  alias Bolognesa.Libraries.Domain.Entities.Library

  @type attrs :: %{
          optional(:name | :path) => String.t(),
          optional(:content_type) => Library.content_type()
        }
  @type error :: :invalid_name | :invalid_path | :invalid_content_type
  @type t :: %__MODULE__{
          name: String.t(),
          path: String.t(),
          content_type: Library.content_type()
        }

  defstruct [:name, :path, :content_type]

  @spec new(attrs()) :: {:ok, t()} | {:error, error()}
  def new(attrs) when is_map(attrs) do
    with {:ok, name} <- validate_name(Map.get(attrs, :name)),
         {:ok, path} <- validate_path(Map.get(attrs, :path)),
         {:ok, content_type} <- validate_content_type(Map.get(attrs, :content_type)) do
      {:ok, %__MODULE__{name: name, path: path, content_type: content_type}}
    end
  end

  def new(_), do: {:error, :invalid_name}

  defp validate_content_type(type) when type in [:movie, :series, :music], do: {:ok, type}
  defp validate_content_type(_), do: {:error, :invalid_content_type}

  defp validate_name(name) when is_binary(name) do
    if String.valid?(name), do: trimmed_name(name), else: {:error, :invalid_name}
  end

  defp validate_name(_), do: {:error, :invalid_name}

  defp trimmed_name(name) do
    name = String.trim(name)
    if byte_size(name) in 1..120, do: {:ok, name}, else: {:error, :invalid_name}
  end

  defp validate_path(path) when is_binary(path) do
    if String.valid?(path), do: trimmed_path(path), else: {:error, :invalid_path}
  end

  defp validate_path(_), do: {:error, :invalid_path}

  defp trimmed_path(path) do
    path = String.trim(path)

    if Path.type(path) == :absolute and byte_size(path) in 2..4096 and
         :binary.match(path, <<0>>) == :nomatch,
       do: {:ok, path},
       else: {:error, :invalid_path}
  end
end

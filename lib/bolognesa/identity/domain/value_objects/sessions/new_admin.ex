defmodule Bolognesa.Identity.Domain.ValueObjects.Sessions.NewAdmin do
  @moduledoc "Validated details for the administrator before persistence."
  alias Bolognesa.Identity.Domain.Entities.User

  @type attrs :: %{optional(:name | :email | :password) => String.t()}
  @type validation_errors :: %{optional(:name | :email | :password) => String.t()}
  @type t :: %__MODULE__{
          name: User.name(),
          email: User.email(),
          password: User.password()
        }

  @derive {Inspect, except: [:password]}
  defstruct [:name, :email, :password]

  @email_pattern ~r/\A[a-z0-9.!#$%&'*+\/?^_`{|}~-]+@[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?)+\z/

  @spec new(attrs()) :: {:ok, t()} | {:error, {:invalid, validation_errors()}}
  def new(attrs) when is_map(attrs) do
    name = normalize_name(Map.get(attrs, :name))
    email = normalize_email(Map.get(attrs, :email))
    password = Map.get(attrs, :password)
    errors = validation_errors(name, email, password)

    if map_size(errors) == 0 do
      {:ok, %__MODULE__{name: name, email: email, password: password}}
    else
      {:error, {:invalid, errors}}
    end
  end

  def new(_),
    do: {:error, {:invalid, %{name: "invalid", email: "invalid", password: "invalid"}}}

  defp normalize_name(value) when is_binary(value) do
    if String.valid?(value), do: String.trim(value), else: nil
  end

  defp normalize_name(_), do: nil

  defp normalize_email(value) when is_binary(value) do
    if String.valid?(value) and ascii?(value),
      do: value |> String.trim() |> String.downcase(),
      else: nil
  end

  defp normalize_email(_), do: nil

  defp validation_errors(name, email, password) do
    %{}
    |> validate_name(name)
    |> validate_email(email)
    |> validate_password(password)
  end

  defp validate_name(errors, name) do
    if is_binary(name) and byte_size(name) in 1..120,
      do: errors,
      else: Map.put(errors, :name, "invalid")
  end

  defp validate_email(errors, email) do
    if is_binary(email) and byte_size(email) <= 254 and Regex.match?(@email_pattern, email),
      do: errors,
      else: Map.put(errors, :email, "invalid")
  end

  defp validate_password(errors, password) do
    if is_binary(password) and byte_size(password) in 12..72 and
         :binary.match(password, <<0>>) == :nomatch,
       do: errors,
       else: Map.put(errors, :password, "invalid")
  end

  defp ascii?(value), do: value |> :binary.bin_to_list() |> Enum.all?(&(&1 < 128))
end

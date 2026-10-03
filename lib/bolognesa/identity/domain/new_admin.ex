defmodule Bolognesa.Identity.Domain.NewAdmin do
  @moduledoc "Validated details for the administrator before persistence."
  alias Bolognesa.Identity.Domain.User

  @derive {Inspect, except: [:password]}
  defstruct [:name, :email, :password]

  @type attrs :: %{optional(:name | :email | :password) => String.t()}
  @type validation_errors :: %{optional(:name | :email | :password) => String.t()}
  @type t :: %__MODULE__{
          name: User.name(),
          email: User.email(),
          password: User.password()
        }

  @email_pattern ~r/\A[a-z0-9.!#$%&'*+\/?^_`{|}~-]+@[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?)+\z/

  @spec new(attrs()) :: {:ok, t()} | {:error, {:invalid, validation_errors()}}
  def new(attrs) when is_map(attrs) do
    name = Map.get(attrs, :name)
    email = Map.get(attrs, :email)
    password = Map.get(attrs, :password)

    name = if is_binary(name) and String.valid?(name), do: String.trim(name), else: nil

    email =
      if is_binary(email) and String.valid?(email) and ascii?(email),
        do: email |> String.trim() |> String.downcase(),
        else: nil

    errors = %{}

    errors =
      if is_binary(name) and byte_size(name) in 1..120,
        do: errors,
        else: Map.put(errors, :name, "invalid")

    errors =
      if is_binary(email) and byte_size(email) <= 254 and Regex.match?(@email_pattern, email),
        do: errors,
        else: Map.put(errors, :email, "invalid")

    errors =
      if is_binary(password) and byte_size(password) in 12..72 and
           :binary.match(password, <<0>>) == :nomatch,
         do: errors,
         else: Map.put(errors, :password, "invalid")

    if map_size(errors) == 0 do
      {:ok, %__MODULE__{name: name, email: email, password: password}}
    else
      {:error, {:invalid, errors}}
    end
  end

  def new(_),
    do: {:error, {:invalid, %{name: "invalid", email: "invalid", password: "invalid"}}}

  defp ascii?(value), do: value |> :binary.bin_to_list() |> Enum.all?(&(&1 < 128))
end

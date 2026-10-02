defmodule Bolognesa.Identity.Domain.User do
  @moduledoc "Identity rules independent of the persistence representation."
  defstruct [:id, :name, :email, :role]

  @type t :: %__MODULE__{id: integer() | nil, name: String.t(), email: String.t(), role: :admin}

  @email_pattern ~r/\A[a-z0-9.!#$%&'*+\/?^_`{|}~-]+@[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?)+\z/

  def new_admin(attrs) when is_map(attrs) do
    name = value(attrs, :name)
    email = value(attrs, :email)
    password = value(attrs, :password)

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
      {:ok, %__MODULE__{name: name, email: email, role: :admin}}
    else
      {:error, {:invalid, errors}}
    end
  end

  def new_admin(_),
    do: {:error, {:invalid, %{name: "invalid", email: "invalid", password: "invalid"}}}

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp ascii?(value), do: value |> :binary.bin_to_list() |> Enum.all?(&(&1 < 128))
end

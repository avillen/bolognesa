defmodule Bolognesa.Libraries.Domain.ValueObjects.Files.NewMediaFile do
  @moduledoc "Validated physical file details before inventory persistence."

  defstruct [:relative_path, :size_bytes, :modified_at]

  @type attrs :: %{
          optional(:relative_path) => binary(),
          optional(:size_bytes) => non_neg_integer(),
          optional(:modified_at) => DateTime.t()
        }
  @type t :: %__MODULE__{
          relative_path: binary(),
          size_bytes: non_neg_integer(),
          modified_at: DateTime.t()
        }

  @spec new(attrs()) :: {:ok, t()} | {:error, :invalid_entry}
  def new(attrs) when is_map(attrs) do
    with true <- Enum.all?(Map.keys(attrs), &is_atom/1),
         true <- valid_path?(Map.get(attrs, :relative_path)),
         true <- valid_size?(Map.get(attrs, :size_bytes)),
         true <- valid_modified_at?(Map.get(attrs, :modified_at)) do
      {:ok, struct!(__MODULE__, Map.take(attrs, [:relative_path, :size_bytes, :modified_at]))}
    else
      _ -> {:error, :invalid_entry}
    end
  end

  def new(_), do: {:error, :invalid_entry}

  defp valid_path?(path) when is_binary(path) do
    :binary.match(path, <<0>>) == :nomatch and
      Enum.all?(:binary.split(path, "/", [:global]), &(&1 not in ["", ".", ".."]))
  end

  defp valid_path?(_), do: false

  defp valid_size?(size), do: is_integer(size) and size >= 0

  defp valid_modified_at?(%DateTime{
         calendar: Calendar.ISO,
         time_zone: "Etc/UTC",
         utc_offset: 0,
         std_offset: 0,
         year: year,
         month: month,
         day: day,
         hour: hour,
         minute: minute,
         second: second,
         microsecond: {microsecond, precision}
       })
       when is_integer(year) and is_integer(month) and is_integer(day) and
              is_integer(hour) and is_integer(minute) and is_integer(second) and
              is_integer(microsecond) and is_integer(precision) do
    match?({:ok, _}, Date.new(year, month, day)) and
      match?({:ok, _}, Time.new(hour, minute, second, {microsecond, precision}))
  end

  defp valid_modified_at?(_), do: false
end

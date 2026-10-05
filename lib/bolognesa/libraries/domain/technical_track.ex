defmodule Bolognesa.Libraries.Domain.TechnicalTrack do
  @moduledoc "A bounded, normalized video, audio or subtitle track."

  defstruct [:kind, :codec, :width, :height, :channels, :language]

  @type kind :: :video | :audio | :subtitle
  @type t :: %__MODULE__{
          kind: kind(),
          codec: String.t() | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          channels: pos_integer() | nil,
          language: String.t() | nil
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_data}
  def new(%{kind: kind} = attrs) when kind in [:video, :audio, :subtitle] do
    codec = Map.get(attrs, :codec)
    width = Map.get(attrs, :width)
    height = Map.get(attrs, :height)
    channels = Map.get(attrs, :channels)
    language = Map.get(attrs, :language)

    if valid_text?(codec, 128) and valid_number?(width) and valid_number?(height) and
         valid_number?(channels) and valid_text?(language, 16) do
      {:ok,
       %__MODULE__{
         kind: kind,
         codec: codec,
         width: width,
         height: height,
         channels: channels,
         language: language
       }}
    else
      {:error, :invalid_data}
    end
  end

  def new(_), do: {:error, :invalid_data}

  defp valid_text?(nil, _max), do: true

  defp valid_text?(value, max) when is_binary(value),
    do: byte_size(value) in 1..max and String.valid?(value)

  defp valid_text?(_, _max), do: false

  defp valid_number?(nil), do: true
  defp valid_number?(value), do: is_integer(value) and value > 0 and value <= 65_535
end

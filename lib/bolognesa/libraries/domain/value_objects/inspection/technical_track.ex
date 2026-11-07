defmodule Bolognesa.Libraries.Domain.ValueObjects.Inspection.TechnicalTrack do
  @moduledoc "A bounded, normalized video, audio or subtitle track."

  @type kind :: :video | :audio | :subtitle
  @type t :: %__MODULE__{
          kind: kind(),
          codec: String.t() | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          channels: pos_integer() | nil,
          language: String.t() | nil,
          index: non_neg_integer() | nil,
          profile: String.t() | nil,
          level: non_neg_integer() | nil,
          pixel_format: String.t() | nil,
          bit_depth: pos_integer() | nil,
          frame_rate: String.t() | nil,
          bit_rate: pos_integer() | nil,
          sample_rate: pos_integer() | nil,
          default?: boolean() | nil,
          attached_picture?: boolean() | nil,
          color_transfer: String.t() | nil,
          color_primaries: String.t() | nil,
          color_space: String.t() | nil
        }

  defstruct [
    :kind,
    :codec,
    :width,
    :height,
    :channels,
    :language,
    :index,
    :profile,
    :level,
    :pixel_format,
    :bit_depth,
    :frame_rate,
    :bit_rate,
    :sample_rate,
    :default?,
    :attached_picture?,
    :color_transfer,
    :color_primaries,
    :color_space
  ]

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_data}
  def new(%{kind: kind} = attrs) when kind in [:video, :audio, :subtitle] do
    codec = Map.get(attrs, :codec)
    width = Map.get(attrs, :width)
    height = Map.get(attrs, :height)
    channels = Map.get(attrs, :channels)
    language = Map.get(attrs, :language)

    if valid_text?(codec, 128) and valid_number?(width) and valid_number?(height) and
         valid_number?(channels) and valid_text?(language, 16) do
      base = %__MODULE__{
        kind: kind,
        codec: codec,
        width: width,
        height: height,
        channels: channels,
        language: language
      }

      {:ok, struct!(base, negotiation_facts(attrs))}
    else
      {:error, :invalid_data}
    end
  end

  def new(_), do: {:error, :invalid_data}

  defp negotiation_facts(attrs) do
    texts =
      for field <- [:profile, :pixel_format, :color_transfer, :color_primaries, :color_space],
          into: %{} do
        value = Map.get(attrs, field)

        {field,
         if(valid_text?(value, 128) and value not in ["unknown", "unspecified", "N/A"], do: value)}
      end

    numbers =
      for {field, bounds} <- [
            index: {0, 65_535},
            level: {0, 255},
            bit_depth: {1, 64},
            bit_rate: {1, 10_000_000_000},
            sample_rate: {1, 768_000}
          ],
          into: %{} do
        {minimum, maximum} = bounds
        value = Map.get(attrs, field)
        {field, bounded_number(value, minimum, maximum)}
      end

    flags =
      for field <- [:default?, :attached_picture?], into: %{} do
        value = Map.get(attrs, field)
        {field, if(is_boolean(value), do: value)}
      end

    texts
    |> Map.merge(numbers)
    |> Map.merge(flags)
    |> Map.put(:frame_rate, frame_rate(Map.get(attrs, :frame_rate)))
  end

  defp bounded_number(value, minimum, maximum)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: value

  defp bounded_number(_, _, _), do: nil

  defp frame_rate(value) when is_binary(value) and byte_size(value) <= 32 do
    case String.split(value, "/") do
      [numerator, denominator] ->
        with {n, ""} <- Integer.parse(numerator),
             {d, ""} <- Integer.parse(denominator),
             true <-
               n > 0 and n <= 1_000_000_000 and d > 0 and d <= 1_000_000_000 and n / d <= 1_000 do
          value
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp frame_rate(_), do: nil

  defp valid_text?(nil, _max), do: true

  defp valid_text?(value, max) when is_binary(value),
    do: byte_size(value) in 1..max and String.valid?(value)

  defp valid_text?(_, _max), do: false

  defp valid_number?(nil), do: true
  defp valid_number?(value), do: is_integer(value) and value > 0 and value <= 65_535
end

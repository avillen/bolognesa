defmodule Bolognesa.Libraries.Infrastructure.Services.CodecConfiguration do
  @moduledoc "Extract bounded codec identifiers from decoder configuration records."
  import Bitwise

  @max_record_bytes 4_096

  @spec from_probe(map()) :: String.t() | nil
  def from_probe(stream) do
    case decode_dump(stream["extradata"]) do
      {:ok, record} -> identifier(stream["codec_name"], record, stream["codec_tag_string"])
      _ -> nil
    end
  end

  @spec identifier(String.t() | nil, binary(), String.t() | nil) :: String.t() | nil
  def identifier(codec, record, tag)
      when is_binary(record) and byte_size(record) <= @max_record_bytes,
      do: codec_identifier(codec, record, tag)

  def identifier(_, _, _), do: nil

  defp codec_identifier(
         "h264",
         <<1, profile, compatibility, level, 63::6, length::2, 7::3, count::5, rest::binary>>,
         tag
       )
       when count > 0 and length in [0, 1, 3] and tag in [nil, "avc1", "[0][0][0][0]"] do
    with {:ok, <<pps_count, pps::binary>>} <- units(rest, count, 7),
         true <- pps_count > 0,
         {:ok, extension} <- units(pps, pps_count, 8),
         true <- avc_extension?(extension, profile) do
      "avc1." <> Base.encode16(<<profile, compatibility, level>>)
    else
      _ -> nil
    end
  end

  defp codec_identifier(
         "hevc",
         <<1, space::2, tier::1, profile::5, compatibility::32, constraints::binary-size(6),
           level, 15::4, _segmentation::12, 63::6, _parallel::2, 63::6, _chroma::2, 31::5,
           _luma::3, 31::5, _depth::3, _rate::16, _temporal::6, length::2, count,
           arrays::binary>>,
         tag
       )
       when tag in ["hvc1", "hev1"] and length in [0, 1, 3] and count > 0 do
    case hevc_arrays(arrays, count, []) do
      {:ok, types} ->
        if Enum.all?([32, 33, 34], &(&1 in types)) do
          hevc_identifier(tag, space, tier, profile, compatibility, constraints, level)
        end

      _ ->
        nil
    end
  end

  defp codec_identifier("aac", <<2::5, frequency::4, channels::4, _::bitstring>>, _tag)
       when frequency <= 12 and channels in 1..7, do: "mp4a.40.2"

  defp codec_identifier(_, _, _), do: nil

  defp avc_extension?(<<>>, _profile), do: true

  defp avc_extension?(<<63::6, _::2, 31::5, _::3, 31::5, _::3, count, rest::binary>>, profile)
       when profile in [100, 110, 122, 144] do
    units(rest, count, 13) == {:ok, <<>>}
  end

  defp avc_extension?(_, _), do: false

  defp units(rest, 0, _type), do: {:ok, rest}

  defp units(<<size::16, rest::binary>>, count, type) when size > 0 and byte_size(rest) >= size do
    <<nal::binary-size(^size), tail::binary>> = rest
    if nal_type?(nal, type), do: units(tail, count - 1, type), else: :error
  end

  defp units(_, _, _), do: :error

  defp nal_type?(<<0::1, type::6, _::1, temporal, _::binary>>, expected) when expected >= 32,
    do: type == expected and band(temporal, 7) != 0

  defp nal_type?(<<0::1, _reference::2, type::5, _::binary>>, expected), do: type == expected
  defp nal_type?(_, _), do: false

  defp hevc_arrays(<<>>, 0, types), do: {:ok, types}

  defp hevc_arrays(<<_complete::1, 0::1, type::6, count::16, rest::binary>>, arrays, types)
       when arrays > 0 and count > 0 do
    with {:ok, tail} <- units(rest, count, type) do
      hevc_arrays(tail, arrays - 1, [type | types])
    end
  end

  defp hevc_arrays(_, _, _), do: :error

  defp hevc_identifier(tag, space, tier, profile, compatibility, constraints, level) do
    reversed =
      Enum.reduce(0..31, 0, fn bit, acc ->
        bor(acc, bsl(band(bsr(compatibility, bit), 1), 31 - bit))
      end)

    prefix = elem({"", "A", "B", "C"}, space)
    tier_name = if tier == 0, do: "L", else: "H"

    suffix =
      constraints
      |> :binary.bin_to_list()
      |> Enum.reverse()
      |> Enum.drop_while(&(&1 == 0))
      |> Enum.reverse()
      |> Enum.map_join("", &("." <> Base.encode16(<<&1>>)))

    "#{tag}.#{prefix}#{profile}.#{Integer.to_string(reversed, 16)}.#{tier_name}#{level}#{suffix}"
  end

  defp decode_dump(dump) when is_binary(dump) and byte_size(dump) <= 20_000 do
    dump
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, <<>>}, &decode_line/2)
  end

  defp decode_dump(_), do: :error

  defp decode_line(line, {:ok, acc}) do
    with [address, columns] <- String.split(line, ": ", parts: 2),
         {offset, ""} <- Integer.parse(address, 16),
         true <- offset == byte_size(acc),
         [hex, _ascii] <- String.split(columns, "  ", parts: 2),
         {:ok, bytes} <- Base.decode16(String.replace(hex, " ", ""), case: :mixed),
         true <-
           byte_size(bytes) in 1..16 and byte_size(acc) + byte_size(bytes) <= @max_record_bytes do
      {:cont, {:ok, acc <> bytes}}
    else
      _ -> {:halt, :error}
    end
  end
end

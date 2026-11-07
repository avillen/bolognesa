defmodule Bolognesa.Playback.Domain.ValueObjects.CapabilityReport do
  @moduledoc "Closed version-one observations for server-issued configurations."
  alias Bolognesa.Playback.Domain.ValueObjects.{DeliveryPlan, PlaybackCandidate}

  @type observation :: %{
          transport: DeliveryPlan.transport(),
          support: :supported | :unsupported | :unknown,
          smooth: :yes | :no | :unknown,
          power_efficient: :yes | :no | :unknown
        }
  @type t :: %__MODULE__{
          preference: :auto | :compatible,
          results: %{String.t() => observation()}
        }
  @enforce_keys [:preference, :results]
  defstruct [:preference, :results]

  @spec new(map(), [PlaybackCandidate.t()], String.t()) :: {:ok, t()} | {:error, :invalid_report}
  def new(raw, candidates, generation) when is_map(raw) do
    with true <- keys?(raw, ~w(version generation preference results), []),
         1 <- raw["version"],
         true <- token?(raw["generation"]) and raw["generation"] == generation,
         {:ok, preference} <- preference(raw["preference"]),
         results when is_list(results) and length(results) <= 6 <- raw["results"],
         true <- :erlang.external_size(raw) <= 8_192,
         {:ok, observations} <- observations(results, candidates) do
      {:ok, %__MODULE__{preference: preference, results: observations}}
    else
      _ -> {:error, :invalid_report}
    end
  end

  def new(_, _, _), do: {:error, :invalid_report}

  defp observations(results, candidates) do
    Enum.reduce_while(results, {:ok, %{}}, fn raw, {:ok, acc} ->
      with {:ok, id, result} <- observation(raw, candidates),
           false <- Map.has_key?(acc, id) do
        {:cont, {:ok, Map.put(acc, id, result)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp observation(raw, candidates) when is_map(raw) do
    with true <- keys?(raw, ~w(candidate_id transport support), ~w(smooth power_efficient)),
         id = raw["candidate_id"],
         true <- token?(id),
         %PlaybackCandidate{} = candidate <- Enum.find(candidates, &(&1.id == id)),
         {:ok, transport} <- transport(raw["transport"]),
         true <- transport in candidate.transports,
         {:ok, support} <- support(raw["support"]),
         {:ok, smooth} <- performance(Map.get(raw, "smooth", "unknown")),
         {:ok, power} <- performance(Map.get(raw, "power_efficient", "unknown")) do
      {:ok, id, %{transport: transport, support: support, smooth: smooth, power_efficient: power}}
    else
      _ -> :error
    end
  end

  defp observation(_, _), do: :error

  defp keys?(map, required, optional) do
    Enum.all?(required, &Map.has_key?(map, &1)) and
      Enum.all?(Map.keys(map), &(&1 in required or &1 in optional))
  end

  defp token?(token), do: is_binary(token) and byte_size(token) in 1..64 and String.valid?(token)
  defp preference("auto"), do: {:ok, :auto}
  defp preference("compatible"), do: {:ok, :compatible}
  defp preference(_), do: :error
  defp transport("file"), do: {:ok, :file}
  defp transport("native_hls"), do: {:ok, :native_hls}
  defp transport("hls_js"), do: {:ok, :hls_js}
  defp transport(_), do: :error
  defp support("supported"), do: {:ok, :supported}
  defp support("unsupported"), do: {:ok, :unsupported}
  defp support("unknown"), do: {:ok, :unknown}
  defp support(_), do: :error
  defp performance("yes"), do: {:ok, :yes}
  defp performance("no"), do: {:ok, :no}
  defp performance("unknown"), do: {:ok, :unknown}
  defp performance(_), do: :error
end

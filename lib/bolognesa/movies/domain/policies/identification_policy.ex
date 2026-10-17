defmodule Bolognesa.Movies.Domain.Policies.IdentificationPolicy do
  @moduledoc "Movie matching confidence and bounded automatic retry decisions."

  alias Bolognesa.Movies.Domain.ValueObjects.MovieCandidate

  @type hint :: %{title: String.t(), year: integer() | nil}
  @type failure_reason ::
          :unusable_name
          | :not_configured
          | :rate_limited
          | :provider_unavailable
          | :unauthorized
          | :invalid_response
          | :not_found
  @type failure_action :: {:retry, failure_reason()} | {:fail, failure_reason()}

  @spec needs_review?(hint(), MovieCandidate.t()) :: boolean()
  def needs_review?(hint, candidate) do
    normalize_title(hint.title) != normalize_title(candidate.title) or
      (not is_nil(hint.year) and not is_nil(candidate.year) and hint.year != candidate.year)
  end

  @spec failure_action(failure_reason(), pos_integer()) :: failure_action()
  def failure_action(reason, attempt) do
    safe_reason = safe_reason(reason)

    if safe_reason in [:rate_limited, :provider_unavailable] and attempt < 3,
      do: {:retry, safe_reason},
      else: {:fail, safe_reason}
  end

  defp safe_reason(reason)
       when reason in [
              :unusable_name,
              :not_configured,
              :rate_limited,
              :provider_unavailable,
              :unauthorized,
              :invalid_response,
              :not_found
            ],
       do: reason

  defp safe_reason(_reason), do: :provider_unavailable

  defp normalize_title(title) do
    title
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^a-z0-9]/u, "")
  end
end

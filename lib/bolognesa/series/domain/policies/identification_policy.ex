defmodule Bolognesa.Series.Domain.Policies.IdentificationPolicy do
  @moduledoc "Classifies review outcomes and bounds automatic identification retries."

  @review_reasons [
    :unusable_name,
    :ambiguous_name,
    :invalid_episode_numbers,
    :too_many_episodes,
    :incomplete_episodes,
    :ambiguous_series,
    :no_match
  ]
  @provider_reasons [
    :not_configured,
    :rate_limited,
    :provider_unavailable,
    :unauthorized,
    :invalid_response,
    :not_found
  ]

  @type review_reason ::
          :unusable_name
          | :ambiguous_name
          | :invalid_episode_numbers
          | :too_many_episodes
          | :incomplete_episodes
          | :ambiguous_series
          | :no_match
  @type provider_reason ::
          :not_configured
          | :rate_limited
          | :provider_unavailable
          | :unauthorized
          | :invalid_response
          | :not_found
  @type reason :: review_reason() | provider_reason()
  @type action ::
          {:review, review_reason()}
          | {:retry, :rate_limited | :provider_unavailable}
          | {:fail, provider_reason()}

  @spec failure_action(reason(), pos_integer()) :: action()
  def failure_action(reason, _attempt) when reason in @review_reasons, do: {:review, reason}

  def failure_action(reason, attempt)
      when reason in [:rate_limited, :provider_unavailable] and attempt < 3,
      do: {:retry, reason}

  def failure_action(reason, _attempt) when reason in @provider_reasons, do: {:fail, reason}
  def failure_action(_reason, _attempt), do: {:fail, :invalid_response}
end

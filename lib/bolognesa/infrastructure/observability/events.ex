defmodule Bolognesa.Infrastructure.Observability.Events do
  @moduledoc "Fixed operational event contracts, sanitized before any subscriber sees them."

  @contracts %{
    {:accounts, :setup} => [:completed, :failed],
    {:accounts, :session} => [:completed, :failed, :rejected],
    {:accounts, :preference} => [:completed, :failed],
    {:libraries, :scan} => [
      :requested,
      :started,
      :completed,
      :failed,
      :retryable,
      :stale,
      :rejected
    ],
    {:libraries, :inspection} => [:started, :completed, :failed, :retryable, :stale],
    {:libraries, :reconciliation} => [:recovered, :failed, :retryable],
    {:libraries, :notification} => [:degraded],
    {:movies, :identification} => [
      :requested,
      :started,
      :completed,
      :failed,
      :retryable,
      :stale,
      :rejected
    ],
    {:movies, :correction} => [:completed, :failed, :stale],
    {:movies, :provider} => [:failed],
    {:movies, :reconciliation} => [:recovered, :failed],
    {:series, :identification} => [
      :requested,
      :started,
      :completed,
      :failed,
      :retryable,
      :stale,
      :rejected
    ],
    {:series, :correction} => [:completed, :failed, :stale],
    {:series, :provider} => [:failed],
    {:series, :reconciliation} => [:recovered, :failed],
    {:music, :import} => [:requested, :started, :completed, :failed, :retryable, :stale],
    {:music, :reconciliation} => [:recovered, :failed, :retryable],
    {:playback, :delivery} => [:failed]
  }
  @events for {{context, resource}, outcomes} <- @contracts,
              outcome <- outcomes,
              do: [:bolognesa, context, resource, outcome]
  @ids [:user_id, :library_id, :scan_id, :file_id, :job_id, :attempt, :revision]
  @fields %{
    setup: [:user_id, :reason, :failure_stage, :result],
    session: [:user_id, :reason, :failure_stage, :operation, :result],
    preference: [:user_id, :reason, :failure_stage, :result, :operation],
    scan: [:library_id, :scan_id, :job_id, :attempt, :reason, :failure_stage, :operation, :result],
    inspection: [:library_id, :file_id, :job_id, :attempt, :revision, :reason, :failure_stage],
    identification: [
      :user_id,
      :file_id,
      :job_id,
      :attempt,
      :revision,
      :reason,
      :failure_stage,
      :operation,
      :result
    ],
    correction: [:user_id, :file_id, :revision, :reason, :failure_stage, :result],
    provider: [:user_id, :reason, :failure_stage, :operation],
    import: [
      :library_id,
      :user_id,
      :file_id,
      :job_id,
      :attempt,
      :revision,
      :reason,
      :failure_stage,
      :operation,
      :result
    ],
    reconciliation: [:reason, :failure_stage, :operation],
    notification: [:library_id, :reason, :failure_stage, :operation],
    delivery: [:file_id, :reason, :failure_stage, :resource_type, :status]
  }
  @enums %{
    reason: [
      :unavailable,
      :storage_unavailable,
      :unexpected_failure,
      :attempts_exhausted,
      :source_inaccessible,
      :source_outside_roots,
      :source_changed,
      :entry_unreadable,
      :unsafe_entry,
      :unreadable,
      :unsupported,
      :timeout,
      :tool_unavailable,
      :invalid_output,
      :notification_unavailable,
      :unusable_name,
      :not_configured,
      :rate_limited,
      :provider_unavailable,
      :unauthorized,
      :invalid_response,
      :not_found,
      :wrong_content_type,
      :ambiguous_name,
      :invalid_episode_numbers,
      :too_many_episodes,
      :incomplete_episodes,
      :ambiguous_series,
      :no_match,
      :invalid_credentials,
      :unauthenticated,
      :forbidden,
      :setup_closed,
      :invalid_locale,
      :invalid_choice,
      :manual_locked,
      :scan_in_progress,
      :stale_observation,
      :stale_attempt,
      :invalid_job,
      :missing,
      :invalid_range,
      :unsatisfiable,
      :read_failed,
      :client_closed,
      :send_failed,
      :invalid_reference,
      :empty_read,
      :invalid_input,
      :terminal
    ],
    failure_stage: [
      :admission,
      :persistence,
      :search,
      :details,
      :season,
      :file_access,
      :ffprobe,
      :execution,
      :recovery,
      :notification,
      :import,
      :exhaustion,
      :retry,
      :request_validation,
      :selection,
      :mime,
      :source_validation,
      :range,
      :read,
      :chunk,
      :authentication,
      :session_lookup,
      :session_write,
      :credential_lookup,
      :setup,
      :preference
    ],
    operation: [
      :retry,
      :search,
      :details,
      :season,
      :scan,
      :inspection,
      :identification,
      :import,
      :setup,
      :start,
      :end,
      :resolve,
      :locale,
      :revoke,
      :create,
      :login,
      :logout,
      :install_admin,
      :start_session,
      :end_session,
      :resolve_session,
      :update_locale,
      :subscribe,
      :broadcast,
      :request
    ],
    result: [
      :completed,
      :matched,
      :review,
      :no_match,
      :unidentified,
      :imported,
      :unchanged,
      :created,
      :deleted,
      :revoked,
      :not_found,
      :updated,
      :automatic,
      :manual
    ],
    resource_type: [:movie, :episode, :music, :audio, :video]
  }
  @measurement_fields [:duration_ms, :files_discovered, :recovered_count, :changed_library_count]
  @maximum 9_223_372_036_854_775_807

  @type context :: :accounts | :libraries | :movies | :series | :music | :playback
  @type resource ::
          :setup
          | :session
          | :preference
          | :scan
          | :inspection
          | :identification
          | :correction
          | :provider
          | :import
          | :reconciliation
          | :notification
          | :delivery
  @type outcome ::
          :requested
          | :started
          | :completed
          | :failed
          | :retryable
          | :stale
          | :rejected
          | :recovered
          | :degraded

  @spec events() :: [[atom()]]
  def events, do: @events

  @spec started_at() :: integer()
  def started_at, do: System.monotonic_time(:millisecond)

  @spec elapsed(integer()) :: non_neg_integer()
  def elapsed(started), do: max(started_at() - started, 0)

  @spec emit(context(), resource(), outcome(), map(), map()) :: :ok
  def emit(context, resource, outcome, metadata \\ %{}, measurements \\ %{}) do
    event = [:bolognesa, context, resource, outcome]

    if event in @events do
      {measurements, metadata} = sanitize(event, measurements, metadata)
      :telemetry.execute(event, measurements, metadata)
    end

    :ok
  end

  @doc "Defensive validation also used when an emitter bypasses the supported API."
  @spec sanitize([atom()], map(), map()) :: {map(), map()}
  def sanitize([:bolognesa, _context, resource, _outcome], measurements, metadata) do
    {sanitize_measurements(measurements), sanitize_metadata(resource, metadata)}
  end

  @spec level([atom()], map()) :: Logger.level()
  def level([:bolognesa, :playback, :delivery, :failed], _metadata), do: :warning
  def level([:bolognesa, _context, :provider, :failed], _metadata), do: :warning

  def level([:bolognesa, _context, _resource, outcome], _metadata)
      when outcome in [:stale, :rejected], do: :debug

  def level([:bolognesa, _context, _resource, outcome], _metadata)
      when outcome in [:retryable, :degraded], do: :warning

  def level([:bolognesa, _context, _resource, :failed], _metadata), do: :error
  def level(_event, _metadata), do: :info

  defp sanitize_measurements(measurements) when is_map(measurements) do
    measurements
    |> Map.take(@measurement_fields)
    |> Map.filter(fn {_key, value} -> bounded_number?(value) end)
    |> Map.put(:count, 1)
  end

  defp sanitize_measurements(_measurements), do: %{count: 1}

  defp sanitize_metadata(resource, metadata) when is_map(metadata) do
    metadata
    |> Map.take(Map.get(@fields, resource, []))
    |> Map.filter(fn {key, value} -> valid_field?(key, value) end)
  end

  defp sanitize_metadata(_resource, _metadata), do: %{}

  defp valid_field?(key, value) when key in @ids,
    do: is_integer(value) and value > 0 and value <= @maximum

  defp valid_field?(:status, value), do: is_integer(value) and value in 100..599
  defp valid_field?(key, value), do: value in Map.get(@enums, key, [])

  defp bounded_number?(value), do: is_integer(value) and value >= 0 and value <= @maximum
end

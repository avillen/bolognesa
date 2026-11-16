defmodule Bolognesa.Playback.Application.UseCases.PrepareVideoDelivery do
  @moduledoc "Reauthorize the source and revalidate a typed delivery plan before execution."
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Playback.Application.Ports.Repositories.PlaybackRepository
  alias Bolognesa.Playback.Application.Ports.Services.DeliveryExecutor
  alias Bolognesa.Playback.Application.UseCases.StartVideoPlayback
  alias Bolognesa.Playback.Domain.Policies.Negotiation
  alias Bolognesa.Playback.Domain.ReadModels.Source
  alias Bolognesa.Playback.Domain.ReadModels.TranscodeSession
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan

  @spec call(
          AuthenticatedUser.t() | nil,
          ContentRef.t(),
          pos_integer(),
          DeliveryPlan.t(),
          non_neg_integer(),
          TranscodeSession.stop_reason() | :session_replaced,
          PlaybackRepository.adapter(),
          DeliveryExecutor.adapter()
        ) ::
          DeliveryExecutor.result()
          | {:error, :forbidden | :not_found | :missing | :invalid_offset}
  def call(actor, content_ref, file_id, plan, offset_ms, replace_reason, repository, executor) do
    with {:ok, source} <- StartVideoPlayback.call(actor, content_ref, file_id, repository),
         :ok <- Negotiation.validate_plan(source, plan),
         :ok <- valid_offset(source, offset_ms) do
      executor.prepare(actor.id, content_ref, file_id, source, plan, offset_ms, replace_reason)
    end
  end

  defp valid_offset(%Source{duration_ms: duration}, offset)
       when is_integer(offset) and offset >= 0 and (is_nil(duration) or offset <= duration),
       do: :ok

  defp valid_offset(_, _), do: {:error, :invalid_offset}
end

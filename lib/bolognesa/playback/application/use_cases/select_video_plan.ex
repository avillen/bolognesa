defmodule Bolognesa.Playback.Application.UseCases.SelectVideoPlan do
  @moduledoc "Reauthorize a current source before interpreting its issued capability observations."
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Playback.Application.Ports.Repositories.PlaybackRepository
  alias Bolognesa.Playback.Application.UseCases.StartVideoPlayback
  alias Bolognesa.Playback.Domain.Policies.Negotiation

  alias Bolognesa.Playback.Domain.ValueObjects.CapabilityReport
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef
  alias Bolognesa.Playback.Domain.ValueObjects.DeliveryPlan
  alias Bolognesa.Playback.Domain.ValueObjects.PlaybackCandidate

  @type error ::
          :forbidden
          | :not_found
          | :missing
          | :unavailable
          | :invalid_report
          | Negotiation.error()
  @spec call(
          AuthenticatedUser.t() | nil,
          ContentRef.t(),
          pos_integer(),
          [PlaybackCandidate.t()],
          map(),
          String.t(),
          PlaybackRepository.adapter()
        ) ::
          {:ok, DeliveryPlan.t()} | {:error, error()}
  def call(actor, content_ref, file_id, issued, raw, generation, repository) do
    with {:ok, source} <- StartVideoPlayback.call(actor, content_ref, file_id, repository),
         {:ok, report} <- CapabilityReport.new(raw, issued, generation) do
      Negotiation.select(source, issued, report)
    end
  end
end

defmodule Bolognesa.PlaybackNegotiationFixtures do
  @moduledoc false
  import Phoenix.LiveViewTest
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Playback
  alias Bolognesa.Repo

  @spec inspect!(MediaFileSchema.t(), String.t(), String.t()) :: InspectionSchema.t()
  def inspect!(file, format \\ "mp4", audio_codec \\ "aac") do
    inspection = Repo.get_by(InspectionSchema, media_file_id: file.id) || %InspectionSchema{}

    Repo.insert_or_update!(
      InspectionSchema.changeset(inspection, %{
        media_file_id: file.id,
        token: Ecto.UUID.generate(),
        observed_revision: file.revision,
        state: :succeeded,
        format: format,
        duration_ms: 60_000,
        tracks: %{
          "items" => [
            %{
              "kind" => "video",
              "codec" => "h264",
              "codec_string" => "avc1.42C029",
              "index" => 0,
              "default?" => true,
              "attached_picture?" => false,
              "profile" => "Constrained Baseline",
              "level" => 41,
              "pixel_format" => "yuv420p",
              "bit_depth" => 8,
              "width" => 320,
              "height" => 180,
              "frame_rate" => "24/1",
              "bit_rate" => 800_000,
              "color_transfer" => "bt709",
              "color_primaries" => "bt709",
              "color_space" => "bt709"
            },
            %{
              "kind" => "audio",
              "codec" => audio_codec,
              "codec_string" => if(audio_codec == "aac", do: "mp4a.40.2"),
              "index" => 1,
              "default?" => true,
              "profile" => "LC",
              "sample_rate" => 48_000,
              "channels" => 2,
              "bit_rate" => 128_000
            }
          ]
        }
      })
    )
  end

  @spec report(Phoenix.LiveViewTest.View.t(), String.t() | nil) :: map()
  def report(view, only \\ nil) do
    [encoded] =
      render(view)
      |> LazyHTML.from_document()
      |> LazyHTML.query("[data-playback-probe]")
      |> LazyHTML.attribute("data-playback-probe")

    probe = Jason.decode!(encoded)

    %{
      "version" => 1,
      "generation" => probe["generation"],
      "preference" => "auto",
      "results" =>
        Enum.map(probe["candidates"], fn c ->
          %{
            "candidate_id" => c["id"],
            "transport" => hd(c["transports"]),
            "support" => if(is_nil(only) or only == c["id"], do: "supported", else: "unsupported")
          }
        end)
    }
  end

  @spec negotiate(Phoenix.LiveViewTest.View.t(), String.t() | nil) :: String.t()
  def negotiate(view, only \\ nil),
    do: render_hook(view, "playback_capabilities", report(view, only))

  @spec prepare_transcode(map(), tuple(), pos_integer(), non_neg_integer(), atom()) :: tuple()
  def prepare_transcode(actor, ref, file_id, offset, _old_strategy) do
    inspect!(Repo.get!(MediaFileSchema, file_id))

    with {:ok, _source, candidates} <- Playback.video_candidates(actor, ref, file_id) do
      candidate = Enum.find(candidates, &(&1.plan.mode == :full_conversion))
      Playback.prepare_video(actor, ref, file_id, %{candidate.plan | transport: :hls_js}, offset)
    end
  end
end

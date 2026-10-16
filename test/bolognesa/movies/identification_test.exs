defmodule Bolognesa.Movies.IdentificationTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Movies.Domain.Entities.Identification

  @now ~U[2026-10-11 10:00:00.000000Z]
  @candidates %{"items" => [%{"provider_id" => 42}]}

  test "constructs a complete pending decision without persistence or a clock" do
    assert {:ok, decision} = Identification.new(1, 2, "token")

    assert decision == %Identification{
             media_file_id: 1,
             observed_revision: 2,
             token: "token",
             state: :pending,
             needs_review?: false,
             candidate_data: %{items: []}
           }

    for {id, revision, token} <- [{0, 1, "token"}, {1, 0, "token"}, {1, 1, ""}] do
      assert {:error, :invalid_request} = Identification.new(id, revision, token)
    end
  end

  test "a new request preserves candidates and origin but clears entries and execution" do
    existing = historical_decision(:automatic)
    assert {:ok, requested} = Identification.request(existing, 2, "new")

    assert requested == %Identification{
             media_file_id: 1,
             state: :pending,
             origin: :automatic,
             observed_revision: 2,
             token: "new",
             candidate_data: @candidates,
             needs_review?: false
           }
  end

  test "manual identified and unidentified decisions reject new automatic requests" do
    for state <- [:manual, :manual_unidentified] do
      manual = %{historical_decision(state) | origin: :manual}
      assert {:error, :manual_locked} = Identification.request(manual, 2, "new")
    end

    assert {:error, :invalid_request} = Identification.request(pending(), 0, "new")
    assert {:ok, %{state: :pending}} = Identification.request(nil, 1, "legacy-token")
  end

  test "starting preserves an already linked job when no new job is supplied" do
    linked = %{pending() | job_id: 7}
    assert {:ok, started} = Identification.start(linked, nil, @now)
    assert started == %{linked | started_at: @now}
    assert {:ok, relinked} = Identification.start(linked, 8, @now)
    assert relinked == %{linked | started_at: @now, job_id: 8}
  end

  test "automatic completion preserves token revision and execution fields" do
    existing = %{pending() | job_id: 7, started_at: @now}
    result = %{candidate_data: @candidates, needs_review?: true, failure_reason: nil}
    assert {:ok, completed} = Identification.complete(existing, 42, result, @now)

    assert completed == %{
             existing
             | state: :automatic,
               origin: :automatic,
               movie_id: 42,
               candidate_data: @candidates,
               needs_review?: true,
               finished_at: @now
           }
  end

  test "completion without entries records the unmatched review reason" do
    result = %{candidate_data: @candidates, needs_review?: true, failure_reason: "no_match"}
    assert {:ok, completed} = Identification.complete(pending(), nil, result, @now)
    assert completed.state == :unmatched
    assert completed.origin == :automatic
    assert completed.failure_reason == "no_match"
    assert completed.movie_id == nil
    assert completed.needs_review?
  end

  test "failure preserves candidates origin and linked execution" do
    existing = %{
      pending()
      | candidate_data: @candidates,
        origin: :automatic,
        job_id: 7,
        started_at: @now
    }

    assert {:ok, failed} = Identification.fail(existing, "provider_unavailable", @now)

    assert failed == %{
             existing
             | state: :failed,
               failure_reason: "provider_unavailable",
               needs_review?: true,
               finished_at: @now
           }
  end

  test "correction replaces the complete set and clears automatic execution" do
    for state <- [:pending, :automatic, :unmatched, :failed, :manual, :manual_unidentified] do
      existing = historical_decision(state)

      for ids <- [43, nil] do
        assert {:ok, corrected} = Identification.correct(existing, 2, "manual-token", ids, @now)

        assert corrected == %Identification{
                 media_file_id: 1,
                 state: if(is_nil(ids), do: :manual_unidentified, else: :manual),
                 origin: :manual,
                 observed_revision: 2,
                 token: "manual-token",
                 movie_id: ids,
                 candidate_data: %{"items" => []},
                 needs_review?: false,
                 finished_at: @now
               }
      end
    end
  end

  test "automatic transitions reject every nonpending state and manual origin" do
    result = %{candidate_data: @candidates, needs_review?: false, failure_reason: nil}

    decisions =
      Enum.map(
        [:automatic, :unmatched, :failed, :manual, :manual_unidentified],
        &historical_decision/1
      ) ++ [%{pending() | origin: :manual}]

    for decision <- decisions do
      assert {:error, :invalid_transition} = Identification.start(decision, nil, @now)
      assert {:error, :invalid_transition} = Identification.fail(decision, "error", @now)
      assert {:error, :invalid_transition} = Identification.complete(decision, nil, result, @now)
    end
  end

  test "invalid completion and correction inputs leave no new decision" do
    result = %{candidate_data: @candidates, needs_review?: false, failure_reason: nil}

    for ids <- [[0], [42, 42], :invalid] do
      assert {:error, :invalid_result} = Identification.complete(pending(), ids, result, @now)

      assert {:error, :invalid_correction} =
               Identification.correct(pending(), 2, "new", ids, @now)
    end

    assert {:error, :invalid_result} = Identification.complete(pending(), nil, %{}, @now)
    assert {:error, :invalid_correction} = Identification.correct(pending(), 0, "new", nil, @now)
    assert {:error, :invalid_correction} = Identification.correct(pending(), 1, "", [], @now)
  end

  defp pending do
    %Identification{
      media_file_id: 1,
      state: :pending,
      observed_revision: 1,
      token: "old",
      needs_review?: false,
      candidate_data: %{items: []}
    }
  end

  defp historical_decision(state) do
    %{
      pending()
      | state: state,
        origin: :automatic,
        movie_id: 42,
        candidate_data: @candidates,
        needs_review?: true,
        failure_reason: "old",
        job_id: 7,
        started_at: @now,
        finished_at: @now
    }
  end
end

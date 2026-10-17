defmodule Bolognesa.Movies.IdentificationPolicyTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Movies.Domain.Policies.IdentificationPolicy

  test "transient errors stop retrying on the third attempt" do
    for reason <- [:rate_limited, :provider_unavailable] do
      assert {:retry, ^reason} = IdentificationPolicy.failure_action(reason, 1)
      assert {:retry, ^reason} = IdentificationPolicy.failure_action(reason, 2)
      assert {:fail, ^reason} = IdentificationPolicy.failure_action(reason, 3)
    end

    assert {:fail, :not_configured} = IdentificationPolicy.failure_action(:not_configured, 1)
  end

  test "matching ignores accents and punctuation but requires compatible known years" do
    hint = %{title: "Élan: Film", year: 2001}

    candidate = %Bolognesa.Movies.Domain.ValueObjects.MovieCandidate{
      provider_id: 1,
      title: "elan film",
      year: 2001
    }

    refute IdentificationPolicy.needs_review?(hint, candidate)
    refute IdentificationPolicy.needs_review?(hint, %{candidate | year: nil})
    assert IdentificationPolicy.needs_review?(hint, %{candidate | year: 2002})
    assert IdentificationPolicy.needs_review?(hint, %{candidate | title: "Another"})
  end
end

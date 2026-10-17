defmodule Bolognesa.Series.IdentificationPolicyTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Series.Domain.Policies.IdentificationPolicy

  test "transient errors stop retrying on the third attempt" do
    for reason <- [:rate_limited, :provider_unavailable] do
      assert {:retry, ^reason} = IdentificationPolicy.failure_action(reason, 1)
      assert {:retry, ^reason} = IdentificationPolicy.failure_action(reason, 2)
      assert {:fail, ^reason} = IdentificationPolicy.failure_action(reason, 3)
    end

    assert {:fail, :not_configured} = IdentificationPolicy.failure_action(:not_configured, 1)
  end

  test "incomplete selections require review instead of another provider retry" do
    assert {:review, :incomplete_episodes} =
             IdentificationPolicy.failure_action(:incomplete_episodes, 1)

    assert {:review, :no_match} = IdentificationPolicy.failure_action(:no_match, 3)
  end
end

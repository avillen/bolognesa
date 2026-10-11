defmodule BolognesaWeb.EndpointOriginPolicyTest do
  use ExUnit.Case, async: true

  alias BolognesaWeb.EndpointOriginPolicy

  test "uses the connection host while keeping origin validation enabled" do
    assert EndpointOriginPolicy.from_env("conn") == :conn
  end

  test "keeps Phoenix's configured host check by default" do
    assert EndpointOriginPolicy.from_env(nil) == true
    assert EndpointOriginPolicy.from_env("") == true
    assert EndpointOriginPolicy.from_env("true") == true
  end

  test "rejects unknown origin check modes" do
    assert_raise ArgumentError, fn -> EndpointOriginPolicy.from_env("false") end
  end
end

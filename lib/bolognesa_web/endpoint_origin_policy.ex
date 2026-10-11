defmodule BolognesaWeb.EndpointOriginPolicy do
  @moduledoc false

  @spec from_env(String.t() | nil) :: true | :conn
  def from_env(value) when value in [nil, "", "true"], do: true
  def from_env("conn"), do: :conn

  def from_env(value) do
    raise ArgumentError, "invalid PHX_CHECK_ORIGIN value: #{inspect(value)}"
  end
end

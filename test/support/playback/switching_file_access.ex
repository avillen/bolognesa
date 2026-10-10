defmodule Bolognesa.Test.SwitchingFileAccess do
  @moduledoc false

  @spec lstat(binary(), keyword()) :: {:ok, File.Stat.t()} | {:error, atom()}
  def lstat(path, opts) do
    case Process.get(:playback_switch_on_lstat) do
      %{path: ^path, from: from, moved: moved, target: target} ->
        Process.delete(:playback_switch_on_lstat)
        File.rename!(from, moved)
        File.ln_s!(target, from)
        File.lstat(path, opts)

      _ ->
        File.lstat(path, opts)
    end
  end
end

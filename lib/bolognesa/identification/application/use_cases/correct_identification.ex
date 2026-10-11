defmodule Bolognesa.Identification.Application.UseCases.CorrectIdentification do
  @moduledoc "Resolve an identification by an administrator's explicit choice."
  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Identity

  @spec call(
          Bolognesa.Identity.Domain.Actor.t(),
          pos_integer(),
          :unidentified | {:tmdb, pos_integer()},
          module(),
          module()
        ) ::
          {:ok, Identification.t()}
          | {:error,
             :forbidden | :not_found | :unavailable | :invalid_choice | :wrong_content_type}
  def call(actor, file_id, choice, repository, provider) do
    with :ok <- Identity.authorize(actor, :admin),
         {:ok, file} <- repository.find_file(file_id),
         :ok <- movie_file(file),
         {:ok, details} <- details(choice, provider) do
      repository.correct(file_id, details)
    end
  end

  defp movie_file(%{content_type: :movie}), do: :ok
  defp movie_file(_), do: {:error, :wrong_content_type}

  defp details(:unidentified, _provider), do: {:ok, :unidentified}

  defp details({:tmdb, id}, provider) when is_integer(id) and id > 0 do
    case provider.details(id) do
      {:ok, %{provider_id: ^id} = details} -> {:ok, details}
      {:error, :not_found} -> {:error, :not_found}
      _ -> {:error, :unavailable}
    end
  end

  defp details(_, _provider), do: {:error, :invalid_choice}
end

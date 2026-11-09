defmodule GuruSignal.Monitoring.EndpointURL do
  @moduledoc "URL syntax policy. This does not authorize an outbound connection."

  @host_label ~r/\A[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\z/

  def validate(url) when is_binary(url) do
    with false <- Regex.match?(~r/[\s\x00-\x1F\x7F\\]/u, url),
         {:ok, uri} <- URI.new(url),
         true <- uri.scheme in ["http", "https"],
         true <- is_binary(uri.host) and uri.host != "",
         true <- is_nil(uri.userinfo) and is_nil(uri.fragment),
         true <- valid_host?(uri.host),
         true <- uri.port == if(uri.scheme == "https", do: 443, else: 80) do
      :ok
    else
      _ ->
        {:error,
         "must be an HTTP or HTTPS URL without credentials or fragments, using its standard port"}
    end
  end

  defp valid_host?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _address} ->
        true

      {:error, _reason} ->
        labels = host |> String.replace_suffix(".", "") |> String.split(".")
        byte_size(host) <= 253 and Enum.all?(labels, &Regex.match?(@host_label, &1))
    end
  end
end

defmodule GuruSignal.Monitoring.Destination do
  @moduledoc "Validates every resolved address and returns a pinned connection destination."
  alias GuruSignal.Monitoring.{DNSResolver, EndpointURL, IPPolicy}

  @local_suffixes ["localhost", "local", "internal", "home.arpa", "onion", "invalid", "test"]

  def resolve(url, resolver \\ DNSResolver) do
    with :ok <- EndpointURL.validate(url),
         {:ok, uri} <- URI.new(url) do
      host = uri.host |> String.downcase() |> String.replace_suffix(".", "")
      uri = %{uri | host: host}

      case :inet.parse_address(String.to_charlist(host)) do
        {:ok, address} -> authorize(uri, [address])
        {:error, _} -> resolve_hostname(uri, resolver)
      end
    else
      _ -> {:error, :blocked_destination}
    end
  end

  defp resolve_hostname(uri, resolver) do
    local? =
      not String.contains?(uri.host, ".") or
        Enum.any?(@local_suffixes, &(uri.host == &1 or String.ends_with?(uri.host, "." <> &1)))

    if local? do
      {:error, :blocked_destination}
    else
      case resolver.resolve(uri.host) do
        {:ok, addresses} when is_list(addresses) -> authorize(uri, addresses)
        _ -> {:error, :connection}
      end
    end
  end

  defp authorize(uri, addresses) do
    if addresses != [] and length(addresses) <= 32 and Enum.all?(addresses, &IPPolicy.public?/1) do
      address = Enum.find(addresses, &(tuple_size(&1) == 4)) || hd(addresses)
      {:ok, %{uri: uri, address: address}}
    else
      {:error, :blocked_destination}
    end
  end
end

defmodule GuruSignal.Monitoring.DNSResolver do
  @moduledoc "Resolves both address families; the caller bounds the overall operation."

  def resolve(host) do
    host = String.to_charlist(host)
    results = [:inet.getaddrs(host, :inet), :inet.getaddrs(host, :inet6)]

    if Enum.all?(results, &(match?({:ok, _}, &1) or &1 == {:error, :nxdomain})) do
      addresses = for {:ok, values} <- results, address <- values, do: address
      if addresses == [], do: {:error, :connection}, else: {:ok, Enum.uniq(addresses)}
    else
      {:error, :connection}
    end
  end
end

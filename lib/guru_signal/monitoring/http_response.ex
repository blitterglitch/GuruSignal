defmodule GuruSignal.Monitoring.HTTPResponse do
  @moduledoc "Bounded, body-discarding accumulation of Mint response events."
  defstruct status: nil, complete?: false, header_bytes: 0, body_bytes: 0

  def consume(state, responses, reference) do
    Enum.reduce_while(responses, {:ok, state}, fn event, {:ok, state} ->
      state = apply_event(state, event, reference)

      if state.header_bytes > 16_384 or state.body_bytes > 65_536 do
        {:halt, {:error, :response_limit}}
      else
        {:cont, {:ok, state}}
      end
    end)
  end

  defp apply_event(state, {:status, ref, status}, ref) when status >= 200 and status <= 599 do
    %{state | status: status}
  end

  defp apply_event(state, {:headers, ref, headers}, ref) do
    bytes =
      Enum.reduce(headers, 0, fn {name, value}, count ->
        count + byte_size(name) + byte_size(value) + 4
      end)

    %{state | header_bytes: state.header_bytes + bytes, complete?: not is_nil(state.status)}
  end

  defp apply_event(state, {:data, ref, data}, ref),
    do: %{state | body_bytes: state.body_bytes + byte_size(data)}

  defp apply_event(state, _event, _ref), do: state
end

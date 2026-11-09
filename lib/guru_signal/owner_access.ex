defmodule GuruSignal.OwnerAccess do
  @moduledoc """
  Single-owner sessions and a node-local login limit.

  Sessions are held in memory and expire after eight hours. Restarting this
  service signs everyone out. This deliberately supports a single app node.
  """
  use GenServer

  @session_ttl 8 * 60 * 60 * 1_000
  @window_ms 60_000
  @attempt_limit 5
  @session_limit 16

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def authenticate(password, server \\ __MODULE__) do
    GenServer.call(server, {:authenticate, password}, 30_000)
  end

  def remaining(token, server \\ __MODULE__) do
    GenServer.call(server, {:remaining, token})
  end

  def revoke(token, server \\ __MODULE__) do
    GenServer.call(server, {:revoke, token})
  end

  def socket_id(token) when is_binary(token) do
    "owner_sessions:" <> Base.url_encode64(:crypto.hash(:sha256, token), padding: false)
  end

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    {:ok,
     %{
       sessions: %{},
       attempts: 0,
       window_started: clock.(),
       clock: clock,
       window_ms: Keyword.get(opts, :window_ms, @window_ms),
       ttl: Keyword.get(opts, :ttl, @session_ttl),
       password_hash: Keyword.get(opts, :password_hash, :configured)
     }}
  end

  @impl true
  def handle_call({:authenticate, password}, _from, state) do
    time = state.clock.()

    state =
      if time - state.window_started >= state.window_ms do
        %{state | attempts: 0, window_started: time}
      else
        state
      end

    hash = password_hash(state)

    cond do
      not is_binary(hash) or hash == "" ->
        {:reply, {:error, :unavailable}, state}

      state.attempts >= @attempt_limit ->
        {:reply, {:error, :rate_limited}, state}

      true ->
        state = %{state | attempts: state.attempts + 1}

        if valid_password?(password, hash) do
          token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
          sessions = Map.reject(state.sessions, fn {_token, expiry} -> expiry <= time end)

          sessions =
            if map_size(sessions) >= @session_limit do
              {oldest, _expiry} = Enum.min_by(sessions, &elem(&1, 1))
              disconnect(oldest)
              Map.delete(sessions, oldest)
            else
              sessions
            end

          {:reply, {:ok, token},
           %{state | sessions: Map.put(sessions, token, state.clock.() + state.ttl)}}
        else
          {:reply, {:error, :invalid}, state}
        end
    end
  end

  def handle_call({:remaining, token}, _from, state) do
    remaining =
      case Map.fetch(state.sessions, token) do
        {:ok, expiry} -> max(expiry - state.clock.(), 0)
        :error -> 0
      end

    {:reply, remaining, state}
  end

  def handle_call({:revoke, token}, _from, state) do
    if is_binary(token), do: disconnect(token)
    {:reply, :ok, %{state | sessions: Map.delete(state.sessions, token)}}
  end

  defp password_hash(%{password_hash: :configured}) do
    Application.get_env(:guru_signal, :owner_password_hash)
  end

  defp password_hash(state), do: state.password_hash

  defp valid_password?(password, hash) when is_binary(password) and byte_size(password) <= 1024 do
    Pbkdf2.verify_pass(password, hash)
  rescue
    # Malformed operator configuration must fail closed, never bypass login.
    ArgumentError -> false
    MatchError -> false
  end

  defp valid_password?(_password, _hash), do: false

  defp disconnect(token) do
    GuruSignalWeb.Endpoint.broadcast(socket_id(token), "disconnect", %{})
  end
end

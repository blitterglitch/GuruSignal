defmodule GuruSignal.OwnerAccessTest do
  use ExUnit.Case, async: true

  alias GuruSignal.OwnerAccess

  setup do
    time = :atomics.new(1, [])
    :atomics.put(time, 1, 1_000)

    server =
      start_supervised!(
        {OwnerAccess,
         name: nil,
         password_hash: Pbkdf2.hash_pwd_salt("test-owner-password", rounds: 1),
         ttl: 100,
         window_ms: 60,
         clock: fn -> :atomics.get(time, 1) end}
      )

    %{server: server, time: time}
  end

  test "rejects invalid input and does not authenticate missing or fabricated sessions", %{
    server: server
  } do
    assert {:error, :invalid} = OwnerAccess.authenticate("wrong", server)
    assert {:error, :invalid} = OwnerAccess.authenticate(nil, server)
    assert {:error, :invalid} = OwnerAccess.authenticate(String.duplicate("x", 1025), server)
    assert OwnerAccess.remaining(nil, server) == 0
    assert OwnerAccess.remaining("fabricated", server) == 0
  end

  test "issues revocable sessions with a fixed expiration", %{server: server, time: time} do
    assert {:ok, token} = OwnerAccess.authenticate("test-owner-password", server)
    assert OwnerAccess.remaining(token, server) == 100
    :atomics.put(time, 1, 1_099)
    assert OwnerAccess.remaining(token, server) == 1
    :atomics.put(time, 1, 1_100)
    assert OwnerAccess.remaining(token, server) == 0

    assert {:ok, another} = OwnerAccess.authenticate("test-owner-password", server)
    assert :ok = OwnerAccess.revoke(another, server)
    assert OwnerAccess.remaining(another, server) == 0
  end

  test "limits all attempts and allows attempts again in the next window", %{
    server: server,
    time: time
  } do
    for _ <- 1..5, do: assert({:error, :invalid} = OwnerAccess.authenticate("wrong", server))
    assert {:error, :rate_limited} = OwnerAccess.authenticate("test-owner-password", server)
    :atomics.put(time, 1, 1_060)
    assert {:ok, _} = OwnerAccess.authenticate("test-owner-password", server)
  end

  test "fails closed when owner authentication is not configured" do
    server = start_supervised!({OwnerAccess, name: nil, password_hash: nil}, id: :unconfigured)
    assert {:error, :unavailable} = OwnerAccess.authenticate("anything", server)
  end
end

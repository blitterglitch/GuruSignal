defmodule GuruSignal.RuntimeConfigTest do
  use ExUnit.Case, async: true

  @base_env [
    {"DATABASE_URL", "ecto://test:test-pass@localhost/smoke"},
    {"SECRET_KEY_BASE", String.duplicate("a", 64)},
    {"PHX_HOST", "status.example.com"},
    {"PHX_BIND_IP", nil},
    {"PHX_SERVER", "false"},
    {"DATABASE_SSL", nil},
    {"DATABASE_CA_CERT_FILE", nil},
    {"MONITORING_ENABLED", "false"},
    {"RETENTION_ENABLED", "false"},
    {"CHECK_RETENTION_DAYS", "30"},
    {"PORT", "8080"},
    {"POOL_SIZE", "2"}
  ]

  test "production defaults to database TLS without starting server or background work" do
    {output, status} =
      read_config([], """
      unless config[:guru_signal][GuruSignal.Repo][:ssl] == true, do: raise("TLS default")
      unless config[:guru_signal][GuruSignalWeb.Endpoint][:http][:ip] == {0,0,0,0,0,0,0,0}, do: raise("bind default")
      unless config[:guru_signal][GuruSignalWeb.Endpoint][:http][:port] == 8080, do: raise("port configuration")
      if config[:guru_signal][GuruSignalWeb.Endpoint][:server] == true, do: raise("server enabled")
      if config[:guru_signal][:monitoring_enabled] or config[:guru_signal][:retention_enabled], do: raise("background work enabled")
      """)

    assert status == 0, output
  end

  test "explicit local plaintext, loopback binding, and a custom CA are supported" do
    {output, status} =
      read_config([{"DATABASE_SSL", "false"}, {"PHX_BIND_IP", "127.0.0.1"}], """
      unless config[:guru_signal][GuruSignal.Repo][:ssl] == false, do: raise("plaintext opt-in")
      unless config[:guru_signal][GuruSignalWeb.Endpoint][:http][:ip] == {127,0,0,1}, do: raise("loopback")
      """)

    assert status == 0, output

    {output, status} =
      read_config([{"DATABASE_CA_CERT_FILE", "/run/secrets/db-ca.pem"}], """
      unless config[:guru_signal][GuruSignal.Repo][:ssl] == [cacertfile: "/run/secrets/db-ca.pem"], do: raise("CA configuration")
      """)

    assert status == 0, output
  end

  test "invalid release configuration fails without including database credentials in errors" do
    for env <- [
          [{"PHX_HOST", nil}],
          [{"SECRET_KEY_BASE", "short"}],
          [{"DATABASE_SSL", "maybe"}],
          [{"DATABASE_SSL", "false"}, {"DATABASE_CA_CERT_FILE", "/run/secrets/db-ca.pem"}],
          [{"PHX_BIND_IP", "not-an-address"}],
          [{"DATABASE_URL", "ecto://test:test-pass@localhost/smoke?ssl=false"}],
          [{"DATABASE_URL", "ecto://test:test-pass@localhost/too/many/segments"}]
        ] do
      {output, status} = read_config(env, "")
      refute status == 0
      refute output =~ "test-pass"
    end
  end

  defp read_config(overrides, assertions) do
    # Each child owns its environment; async tests never mutate the parent environment.
    env = Map.merge(Map.new(@base_env), Map.new(overrides)) |> Map.to_list()
    script = "config = Config.Reader.read!(\"config/runtime.exs\", env: :prod)\n" <> assertions

    System.cmd(System.find_executable("elixir"), ["--erl", "+S 2:2", "-e", script],
      env: env,
      stderr_to_stdout: true
    )
  end
end

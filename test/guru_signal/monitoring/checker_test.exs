defmodule GuruSignal.Monitoring.CheckerTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Monitoring.{Checker, Endpoint}

  defmodule Resolver do
    def resolve(_host), do: {:ok, [{8, 8, 8, 8}]}
  end

  defmodule PrivateResolver do
    def resolve(_host), do: {:ok, [{127, 0, 0, 1}]}
  end

  defmodule HangingResolver do
    def resolve(_host) do
      receive do
        :never -> {:error, :connection}
      end
    end
  end

  defmodule Client do
    def fetch(%{address: {8, 8, 8, 8}, uri: %{path: path}}, _deadline) do
      case path do
        "/ok" ->
          {:ok, 200}

        "/redirect" ->
          {:ok, 302}

        "/status" ->
          {:ok, 503}

        "/crash" ->
          raise "sensitive details must not escape"

        "/throw" ->
          throw("sensitive thrown details must not escape")

        "/exit" ->
          exit("sensitive exit details must not escape")

        "/hang" ->
          receive do
            :never -> {:ok, 200}
          end

        other ->
          {:error, String.to_existing_atom(String.trim_leading(other, "/"))}
      end
    end
  end

  setup do
    supervisor = start_supervised!({Task.Supervisor, max_children: 4})

    endpoint = %Endpoint{
      url: "https://service.example.org/ok",
      expected_status: 200,
      timeout_ms: 1000
    }

    %{
      endpoint: endpoint,
      options: [resolver: Resolver, client: Client, task_supervisor: supervisor]
    }
  end

  test "compares actual and expected HTTP status without following redirects", %{
    endpoint: endpoint,
    options: opts
  } do
    assert %{success: true, http_status: 200, error_category: nil} = Checker.check(endpoint, opts)

    for {path, status} <- [{"/status", 503}, {"/redirect", 302}] do
      assert %{success: false, http_status: ^status, error_category: :unexpected_status} =
               Checker.check(%{endpoint | url: "https://service.example.org" <> path}, opts)
    end

    assert %{success: true, http_status: 302} =
             Checker.check(
               %{endpoint | url: "https://service.example.org/redirect", expected_status: 302},
               opts
             )
  end

  test "normalizes errors and does not expose internal exceptions", %{
    endpoint: endpoint,
    options: opts
  } do
    for category <- [:connection, :tls, :timeout, :response_limit, :protocol] do
      assert %{success: false, http_status: nil, error_category: ^category} =
               Checker.check(%{endpoint | url: "https://service.example.org/#{category}"}, opts)
    end

    assert %{error_category: :internal} =
             outcome = Checker.check(%{endpoint | url: "https://service.example.org/crash"}, opts)

    refute inspect(outcome) =~ "sensitive"
  end

  test "enforces policy before invoking a client", %{endpoint: endpoint, options: opts} do
    assert %{error_category: :blocked_destination} =
             Checker.check(endpoint, Keyword.put(opts, :resolver, PrivateResolver))
  end

  test "task throws and exits become safe outcomes without logging their payloads", %{
    endpoint: endpoint,
    options: opts
  } do
    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        for path <- ["/throw", "/exit"] do
          assert %{success: false, error_category: :internal} =
                   Checker.check(%{endpoint | url: "https://service.example.org" <> path}, opts)
        end
      end)

    refute logs =~ "sensitive"
    assert Task.Supervisor.children(opts[:task_supervisor]) == []
  end

  test "the total deadline covers hanging DNS and HTTP and terminates their tasks", %{
    endpoint: endpoint,
    options: opts
  } do
    endpoint = %{endpoint | timeout_ms: 20}

    assert %{error_category: :timeout} =
             Checker.check(endpoint, Keyword.put(opts, :resolver, HangingResolver))

    assert %{error_category: :timeout} =
             Checker.check(%{endpoint | url: "https://service.example.org/hang"}, opts)

    assert Task.Supervisor.children(opts[:task_supervisor]) == []
  end
end

defmodule GuruSignalWeb.HealthControllerTest do
  use GuruSignalWeb.ConnCase, async: true
  alias GuruSignal.Repo

  test "liveness is public JSON and does not require a database", %{conn: conn} do
    with_unavailable_repo(fn ->
      response = get(conn, ~p"/health/live")
      assert json_response(response, 200) == %{"status" => "ok"}
      assert get_resp_header(response, "cache-control") == ["no-store"]
      assert get_resp_header(response, "set-cookie") == []
    end)
  end

  test "readiness verifies the database without owner authentication", %{conn: conn} do
    response = get(conn, ~p"/health/ready")
    assert json_response(response, 200) == %{"status" => "ok"}
    assert get_resp_header(response, "cache-control") == ["no-store"]
  end

  test "unavailable readiness returns only a generic 503", %{conn: conn} do
    with_unavailable_repo(fn ->
      response = get(conn, ~p"/health/ready")
      assert json_response(response, 503) == %{"status" => "unavailable"}
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end)
  end

  defp with_unavailable_repo(function) do
    previous = Repo.get_dynamic_repo()
    Repo.put_dynamic_repo(:unavailable_health_test_repo)

    try do
      function.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end
end

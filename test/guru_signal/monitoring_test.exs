defmodule GuruSignal.MonitoringTest do
  use GuruSignal.DataCase, async: true

  import GuruSignal.MonitoringFixtures
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.Endpoint

  test "persists configuration, broadcasts changes, and supports update and delete" do
    Monitoring.subscribe()
    endpoint = endpoint_fixture()
    id = endpoint.id
    assert_receive {:endpoint_changed, ^id}
    assert [%Endpoint{id: ^id}] = Monitoring.list_endpoints()
    assert Monitoring.get_endpoint("#{id}") == endpoint

    assert {:ok, updated} = Monitoring.update_endpoint(endpoint, %{name: "API", enabled: false})
    refute updated.enabled
    assert updated.lock_version == 2
    assert_receive {:endpoint_changed, ^id}
    assert {:ok, _} = Monitoring.delete_endpoint(updated)
    assert_receive {:endpoint_changed, ^id}
    assert Monitoring.get_endpoint(id) == nil
  end

  test "invalid changes leave the stored endpoint untouched and do not broadcast" do
    endpoint = endpoint_fixture()
    endpoint_id = endpoint.id
    Monitoring.subscribe()
    assert {:error, changeset} = Monitoring.update_endpoint(endpoint, %{timeout_ms: 20_000})
    assert "must be less than or equal to 10000" in errors_on(changeset).timeout_ms
    assert Monitoring.get_endpoint(endpoint.id) == endpoint
    refute_received {:endpoint_changed, ^endpoint_id}
  end

  test "stale editors cannot overwrite or delete a newer configuration" do
    endpoint = endpoint_fixture()
    first_editor = Monitoring.get_endpoint(endpoint.id)
    second_editor = Monitoring.get_endpoint(endpoint.id)
    assert {:ok, updated} = Monitoring.update_endpoint(first_editor, %{name: "New configuration"})
    assert {:error, unchanged_stale} = Monitoring.update_endpoint(second_editor, %{})
    assert Keyword.has_key?(unchanged_stale.errors, :lock_version)

    assert {:error, changeset} =
             Monitoring.update_endpoint(second_editor, %{name: "Stale configuration"})

    assert Keyword.has_key?(changeset.errors, :lock_version)
    assert {:error, changeset} = Monitoring.delete_endpoint(second_editor)
    assert Keyword.has_key?(changeset.errors, :lock_version)
    assert Monitoring.get_endpoint(endpoint.id) == updated
  end

  test "missing, malformed, and out-of-range identities return nil" do
    for id <- [nil, "invalid", -1, "0", "999999999999999999999999999999999", 123] do
      assert Monitoring.get_endpoint(id) == nil
    end
  end

  for {field, value, constraint} <- [
        {:name, "   ", "endpoints_name_length"},
        {:url, "ftp://example.com", "endpoints_url_shape"},
        {:expected_status, 600, "endpoints_expected_status_range"},
        {:interval_seconds, 30, "endpoints_supported_interval"},
        {:timeout_ms, 0, "endpoints_timeout_range"},
        {:lock_version, 0, "endpoints_positive_version"}
      ] do
    test "database enforces #{constraint} even without a changeset" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        name: "Direct insert",
        url: "https://example.com",
        inserted_at: now,
        updated_at: now
      }

      attrs = Map.put(attrs, unquote(field), unquote(value))

      error = assert_raise Postgrex.Error, fn -> Repo.insert_all(Endpoint, [attrs]) end
      assert error.postgres.constraint == unquote(constraint)
    end
  end
end

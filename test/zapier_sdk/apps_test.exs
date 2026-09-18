defmodule ZapierSDK.AppsTest do
  @moduledoc """
  Guards the input field names the app helpers send.

  These helpers previously shipped field names that no Zapier action accepts
  (Slack's message body is `text`, not `message`; Calendar's window is
  `start_time`/`end_time`, not `time_min`/`time_max`). A wrong key is not a
  compile error and not obviously wrong at the call site, so it is pinned here.
  """

  use ExUnit.Case, async: true

  import Plug.Conn

  alias ZapierSDK.Apps.{GoogleCalendar, GoogleDrive, Slack}
  alias ZapierSDK.{Catalog, Connection}

  setup do
    Catalog.flush()
    :ok
  end

  # Captures the action-run request so a test can assert on what was sent.
  defp capture(action_type) do
    test = self()

    Req.Test.stub(ZapierSDK, fn conn ->
      case conn.request_path do
        "/api/v0/apps" ->
          json(conn, [
            %{"slug" => "app", "key" => "AppCLIAPI", "implementation_id" => "AppCLIAPI@1.0.0"}
          ])

        "/api/v0/actions" ->
          {:ok, body, conn} = read_body(conn)
          _ = body

          json(conn, [
            %{"id" => "core:1", "key" => action_key(conn), "action_type" => action_type}
          ])

        path ->
          handle_run(conn, path, test)
      end
    end)
  end

  # The stub answers whichever action key the SDK asked about, so a single
  # stub works for every helper under test.
  defp action_key(conn) do
    conn.query_string
    |> URI.decode_query()
    |> Map.get("app_key")
    |> then(fn _ -> Process.get(:expected_action_key) end)
  end

  defp handle_run(conn, path, test) do
    if String.ends_with?(path, "/runs") do
      {:ok, body, conn} = read_body(conn)
      send(test, {:run, Jason.decode!(body)["data"]})
      json(conn, %{"id" => "run-1"})
    else
      json(conn, %{"id" => "run-1", "status" => "success", "results" => [], "errors" => []})
    end
  end

  defp json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{"data" => data, "errors" => []}))
  end

  defp run_and_capture(action_key, action_type, fun) do
    Process.put(:expected_action_key, action_key)
    capture(action_type)
    fun.()
    assert_received {:run, request}
    request
  end

  describe "Slack" do
    test "send_message/3 uses the `text` field" do
      request =
        run_and_capture("channel_message", "write", fn ->
          Slack.send_message("#general", "hello", connection: conn("slack"))
        end)

      assert request["action_key"] == "channel_message"
      assert request["action_type"] == "write"
      assert request["inputs"]["channel"] == "#general"
      assert request["inputs"]["text"] == "hello"
      refute Map.has_key?(request["inputs"], "message")
    end

    test "send_dm/3 addresses the recipient through `channel`" do
      request =
        run_and_capture("direct_message", "write", fn ->
          Slack.send_dm("@james", "hi", connection: conn("slack"))
        end)

      assert request["inputs"]["channel"] == "@james"
      assert request["inputs"]["text"] == "hi"
    end
  end

  describe "GoogleCalendar" do
    test "find_events/1 uses start_time/end_time and calendarid" do
      request =
        run_and_capture("event_v2", "search", fn ->
          GoogleCalendar.find_events(
            connection: conn("google-calendar"),
            start_time: "2026-01-01T00:00:00Z",
            end_time: "2026-01-02T00:00:00Z"
          )
        end)

      inputs = request["inputs"]
      assert inputs["calendarid"] == "primary"
      assert inputs["start_time"] == "2026-01-01T00:00:00Z"
      assert inputs["end_time"] == "2026-01-02T00:00:00Z"
      refute Map.has_key?(inputs, "time_min")
      refute Map.has_key?(inputs, "calendar_id")
    end

    test "today_events/1 bounds the search to a single day" do
      request =
        run_and_capture("event_v2", "search", fn ->
          GoogleCalendar.today_events(connection: conn("google-calendar"))
        end)

      today = Date.utc_today() |> Date.to_iso8601()
      assert request["inputs"]["start_time"] =~ today
    end
  end

  describe "GoogleDrive" do
    test "find_file/2 searches by title and omits unset options" do
      request =
        run_and_capture("file_v2", "search", fn ->
          GoogleDrive.find_file("Q3 budget", connection: conn("google-drive"))
        end)

      assert request["action_key"] == "file_v2"
      assert request["inputs"] == %{"title" => "Q3 budget"}
    end

    test "find_folder/2 passes through the drive option" do
      request =
        run_and_capture("folder_v2", "search", fn ->
          GoogleDrive.find_folder("Design", connection: conn("google-drive"), drive: "drive-1")
        end)

      assert request["inputs"]["drive"] == "drive-1"
    end
  end

  test "the connection id travels as authentication_id" do
    request =
      run_and_capture("file_v2", "search", fn ->
        GoogleDrive.find_file("x", connection: conn("google-drive"))
      end)

    assert request["authentication_id"] == "the-uuid"
    assert request["selected_api"] == "AppCLIAPI@1.0.0"
    assert request["action_id"] == "core:1"
  end

  defp conn(app), do: Connection.new(app, "the-uuid")
end

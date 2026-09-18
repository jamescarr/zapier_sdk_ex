defmodule ZapierSDK.HTTPTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias ZapierSDK.{Catalog, Error}

  setup do
    Catalog.flush()
    :ok
  end

  defp respond(status, body) do
    Req.Test.stub(ZapierSDK, fn conn ->
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(body))
    end)
  end

  test "sends the configured bearer token" do
    Req.Test.stub(ZapierSDK, fn conn ->
      assert ["Bearer test-token"] = get_req_header(conn, "authorization")

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{"data" => []}))
    end)

    assert {:ok, []} = ZapierSDK.list_connections()
  end

  test "maps 401 to an authentication error" do
    respond(401, %{"errors" => [%{"detail" => "bad token"}]})

    assert {:error, %Error{type: :authentication_failed, status: 401}} =
             ZapierSDK.list_connections()
  end

  test "maps 429 to a rate-limit error and surfaces retry-after" do
    Req.Test.stub(ZapierSDK, fn conn ->
      conn
      |> put_resp_header("retry-after", "30")
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(%{"errors" => []}))
    end)

    assert {:error, %Error{type: :rate_limited, retry_after_ms: 30_000}} =
             ZapierSDK.list_connections()
  end

  test "includes the server's detail message in HTTP errors" do
    respond(400, %{"errors" => [%{"detail" => "inputs must be an object"}]})

    assert {:error, %Error{type: :http_error, status: 400} = error} =
             ZapierSDK.list_connections()

    assert error.message =~ "inputs must be an object"
  end

  test "maps a transport failure to a transport error" do
    Req.Test.stub(ZapierSDK, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert {:error, %Error{type: :transport_error}} = ZapierSDK.list_connections()
  end

  describe "retry policy" do
    setup do
      previous = Application.get_env(:zapier_sdk, :max_retries)
      Application.put_env(:zapier_sdk, :max_retries, 2)
      on_exit(fn -> Application.put_env(:zapier_sdk, :max_retries, previous) end)
      :ok
    end

    test "retries an idempotent request that fails with a 5xx" do
      counter = :counters.new(1, [])

      Req.Test.stub(ZapierSDK, fn conn ->
        :counters.add(counter, 1, 1)
        send_resp(conn, 500, "boom")
      end)

      assert {:error, %Error{status: 500}} = ZapierSDK.list_connections()
      assert :counters.get(counter, 1) == 3, "expected the initial call plus two retries"
    end

    # Action runs are created with POST. Replaying one would run the action a
    # second time, which for a write means a duplicate message or record.
    test "never retries a non-idempotent request" do
      counter = :counters.new(1, [])
      ZapierSDK.Catalog.flush()

      Req.Test.stub(ZapierSDK, fn conn ->
        case conn.request_path do
          "/api/v0/apps" ->
            json(conn, [%{"slug" => "app", "implementation_id" => "AppCLIAPI@1.0.0"}])

          "/api/v0/actions" ->
            json(conn, [%{"id" => "core:1", "key" => "thing", "action_type" => "write"}])

          _ ->
            :counters.add(counter, 1, 1)
            send_resp(conn, 500, "boom")
        end
      end)

      conn = ZapierSDK.connection("app", "uuid")
      assert {:error, %Error{status: 500}} = ZapierSDK.write(conn, "thing", %{})
      assert :counters.get(counter, 1) == 1, "the action-run POST must not be replayed"
    end

    test "does not retry a 429, surfacing it immediately instead" do
      counter = :counters.new(1, [])

      Req.Test.stub(ZapierSDK, fn conn ->
        :counters.add(counter, 1, 1)

        conn
        |> put_resp_header("retry-after", "30")
        |> send_resp(429, "slow down")
      end)

      assert {:error, %Error{type: :rate_limited}} = ZapierSDK.list_connections()
      assert :counters.get(counter, 1) == 1
    end
  end

  defp json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{"data" => data, "errors" => []}))
  end
end

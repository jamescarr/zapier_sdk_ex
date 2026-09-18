defmodule ZapierSDK.AuthTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias ZapierSDK.{Auth, Error}

  setup do
    # These tests exercise the credential branches, so they need to swap the
    # suite-wide static token out and restore it afterwards.
    previous = Application.get_env(:zapier_sdk, :token)
    on_exit(fn -> Application.put_env(:zapier_sdk, :token, previous) end)
    :ok
  end

  defp with_client_credentials(fun) do
    Application.delete_env(:zapier_sdk, :token)
    Application.put_env(:zapier_sdk, :client_id, "id")
    Application.put_env(:zapier_sdk, :client_secret, "secret")

    try do
      fun.()
    after
      Application.delete_env(:zapier_sdk, :client_id)
      Application.delete_env(:zapier_sdk, :client_secret)
    end
  end

  defp start_auth do
    pid = start_supervised!({Auth, name: :"auth_#{System.unique_integer([:positive])}"})
    Req.Test.allow(ZapierSDK, self(), pid)
    pid
  end

  test "returns a statically configured token without any exchange" do
    Application.put_env(:zapier_sdk, :token, "static-token")
    assert {:ok, "static-token"} = Auth.token()
  end

  test "reports missing credentials clearly" do
    Application.delete_env(:zapier_sdk, :token)

    assert {:error, %Error{type: :no_credentials} = error} = Auth.token()
    assert error.message =~ "ZAPIER_CREDENTIALS_CLIENT_ID"
  end

  test "exchanges client credentials and caches the result" do
    with_client_credentials(fn ->
      counter = :counters.new(1, [])
      auth = start_auth()

      Req.Test.stub(ZapierSDK, fn conn ->
        :counters.add(counter, 1, 1)
        {:ok, body, conn} = read_body(conn)
        params = URI.decode_query(body)

        assert params["grant_type"] == "client_credentials"
        assert params["client_id"] == "id"
        assert params["client_secret"] == "secret"
        assert params["audience"] == "zapier.com"

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{"access_token" => "minted", "expires_in" => 3600}))
      end)

      assert {:ok, "minted"} = Auth.token(auth)
      assert {:ok, "minted"} = Auth.token(auth)
      assert :counters.get(counter, 1) == 1, "expected the token to be cached"
    end)
  end

  test "re-exchanges after invalidation" do
    with_client_credentials(fn ->
      counter = :counters.new(1, [])
      auth = start_auth()

      Req.Test.stub(ZapierSDK, fn conn ->
        :counters.add(counter, 1, 1)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{"access_token" => "minted", "expires_in" => 3600}))
      end)

      assert {:ok, "minted"} = Auth.token(auth)
      Auth.invalidate(auth)
      assert {:ok, "minted"} = Auth.token(auth)
      assert :counters.get(counter, 1) == 2
    end)
  end

  test "surfaces a rejected exchange as an authentication error" do
    with_client_credentials(fn ->
      auth = start_auth()

      Req.Test.stub(ZapierSDK, fn conn ->
        send_resp(conn, 401, Jason.encode!(%{"error" => "invalid_client"}))
      end)

      assert {:error, %Error{type: :authentication_failed, status: 401}} = Auth.token(auth)
    end)
  end

  test "a token expiring within the refresh buffer is not reused" do
    with_client_credentials(fn ->
      counter = :counters.new(1, [])
      auth = start_auth()

      Req.Test.stub(ZapierSDK, fn conn ->
        :counters.add(counter, 1, 1)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          # Shorter than the 60s buffer, so it must never be served from cache.
          Jason.encode!(%{"access_token" => "short", "expires_in" => 5})
        )
      end)

      assert {:ok, "short"} = Auth.token(auth)
      assert {:ok, "short"} = Auth.token(auth)
      assert :counters.get(counter, 1) == 2
    end)
  end
end

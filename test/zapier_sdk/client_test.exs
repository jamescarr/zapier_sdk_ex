defmodule ZapierSDK.ClientTest do
  use ExUnit.Case, async: true

  alias ZapierSDK.{Action, Catalog, Connection, Error, ZapierStub}

  setup do
    # Metadata is cached across calls by design, which would otherwise leak
    # one test's stubbed catalog into the next.
    Catalog.flush()
    :ok
  end

  defp conn, do: Connection.new("google-drive", "conn-uuid")

  describe "run/3" do
    test "returns the results of a finished run" do
      ZapierStub.install(pages: [{[%{"id" => "1", "title" => "Budget"}], nil}])

      assert {:ok, result} = ZapierSDK.run(conn(), Action.search("file_v2", %{}))
      assert result.count == 1
      assert [%{"title" => "Budget"}] = result.data
      assert result.connection_app == "google-drive"
      assert result.action_name == "file_v2"
    end

    test "polls until the run leaves the waiting state" do
      ZapierStub.install(waits: 2, pages: [{[%{"id" => "1"}], nil}])

      assert {:ok, result} = ZapierSDK.run(conn(), Action.search("file_v2", %{}))
      assert result.count == 1
    end

    test "an empty result set is a success, not an error" do
      ZapierStub.install(pages: [{[], nil}])

      assert {:ok, result} = ZapierSDK.run(conn(), Action.search("file_v2", %{}))
      assert result.count == 0
      assert ZapierSDK.Result.empty?(result)
    end

    # The bug that motivated the HTTP rewrite: a run that finishes with errors
    # used to surface as a successful, empty result.
    test "a run that finishes with errors is an error, not an empty success" do
      ZapierStub.install(
        errors: [
          %{"code" => "invalid_input", "title" => "Bad Request", "detail" => "title required"}
        ]
      )

      assert {:error, %Error{} = error} = ZapierSDK.run(conn(), Action.search("file_v2", %{}))
      assert error.type == :action_failed
      assert error.message =~ "title required"
    end

    test "an expired connection gets its own error type" do
      ZapierStub.install(
        errors: [
          %{
            "code" => "authentication_error",
            "title" => "Authentication Error",
            "detail" => "Your authentication has expired, please reconnect your account"
          }
        ]
      )

      assert {:error, %Error{type: :connection_expired} = error} =
               ZapierSDK.run(conn(), Action.search("file_v2", %{}))

      assert error.message =~ "reconnect"
    end
  end

  describe "pagination" do
    test "follows next_page until it is absent" do
      ZapierStub.install(
        pages: [
          {[%{"id" => "1"}, %{"id" => "2"}], 2},
          {[%{"id" => "3"}], nil}
        ]
      )

      assert {:ok, result} = ZapierSDK.run(conn(), Action.search("file_v2", %{}))
      assert result.count == 3
      assert Enum.map(result, & &1["id"]) == ["1", "2", "3"]
    end

    test "max_items stops paging early" do
      ZapierStub.install(
        pages: [
          {[%{"id" => "1"}, %{"id" => "2"}], 2},
          {[%{"id" => "3"}], nil}
        ]
      )

      assert {:ok, result} =
               ZapierSDK.run(conn(), Action.search("file_v2", %{}), max_items: 2)

      assert result.count == 2
    end
  end

  describe "stream/4" do
    test "yields items lazily across pages" do
      ZapierStub.install(
        pages: [
          {[%{"id" => "1"}, %{"id" => "2"}], 2},
          {[%{"id" => "3"}], nil}
        ]
      )

      ids =
        conn()
        |> ZapierSDK.stream("file_v2", %{})
        |> Enum.map(& &1["id"])

      assert ids == ["1", "2", "3"]
    end
  end

  describe "run_many/2" do
    test "returns one result per entry, in order" do
      ZapierStub.install(pages: [{[%{"id" => "1"}], nil}])

      results =
        ZapierSDK.run_many([
          {conn(), Action.search("file_v2", %{})},
          {conn(), Action.search("file_v2", %{})}
        ])

      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "metadata resolution" do
    test "reports the available keys when an action does not exist" do
      ZapierStub.install(
        actions: [
          %{"id" => "core:1", "key" => "file_v2", "action_type" => "search"},
          %{"id" => "core:2", "key" => "folder_v2", "action_type" => "search"}
        ]
      )

      assert {:error, %Error{type: :action_not_found} = error} =
               ZapierSDK.run(conn(), Action.search("nope", %{}))

      assert error.message =~ "nope"
      assert error.details == ["file_v2", "folder_v2"]
    end

    test "reports a missing app" do
      ZapierStub.install(apps: [])

      assert {:error, %Error{type: :app_not_found}} =
               ZapierSDK.run(conn(), Action.search("file_v2", %{}))
    end
  end
end

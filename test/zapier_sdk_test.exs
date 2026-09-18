defmodule ZapierSDKTest do
  use ExUnit.Case, async: true

  alias ZapierSDK.{Action, Catalog, Result, ZapierStub}

  setup do
    Catalog.flush()
    :ok
  end

  describe "action type helpers" do
    test "search/read/write send the matching action_type" do
      for {helper, type} <- [{&ZapierSDK.search/3, "search"}, {&ZapierSDK.write/3, "write"}] do
        Catalog.flush()

        ZapierStub.install(
          actions: [%{"id" => "core:1", "key" => "thing", "action_type" => type}],
          pages: [{[%{"ok" => true}], nil}]
        )

        assert {:ok, %Result{count: 1}} = helper.(:drive, "thing", %{})
      end
    end
  end

  describe "async/5" do
    test "returns a Task that resolves to a result" do
      ZapierStub.install(pages: [{[%{"ok" => true}], nil}])

      task = ZapierSDK.async(:drive, :search, "file_v2", %{})
      assert %Task{} = task
      assert {:ok, %Result{count: 1}} = Task.await(task, 10_000)
    end
  end

  describe "run_many/2" do
    test "accepts named connections" do
      ZapierStub.install(pages: [{[%{"ok" => true}], nil}])

      results =
        ZapierSDK.run_many([
          {:drive, Action.search("file_v2", %{})},
          {:drive, Action.search("file_v2", %{})}
        ])

      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, %Result{}}, &1))
    end
  end

  describe "connection/3" do
    test "builds an ad-hoc connection" do
      conn = ZapierSDK.connection("custom-app", "999")
      assert conn.app == "custom-app"
      assert conn.id == "999"
    end
  end

  describe "discovery" do
    test "list_connections/1 returns the account's connections" do
      ZapierStub.install(
        connections: [%{"id" => "uuid-1", "app_key" => "SlackCLIAPI", "title" => "Slack"}]
      )

      assert {:ok, [%{"id" => "uuid-1"}]} = ZapierSDK.list_connections()
    end

    test "list_apps/1 searches the catalog" do
      ZapierStub.install(apps: [%{"slug" => "slack", "key" => "SlackCLIAPI"}])

      assert {:ok, [%{"slug" => "slack"}]} = ZapierSDK.list_apps(search: "slack")
    end
  end
end

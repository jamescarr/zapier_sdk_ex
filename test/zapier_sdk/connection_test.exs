defmodule ZapierSDK.ConnectionTest do
  use ExUnit.Case, async: true

  alias ZapierSDK.Connection

  describe "new/3" do
    test "creates a connection with required fields" do
      conn = Connection.new("jira-software-cloud", "025841e4-b17e-86f2-b9a4-6ef54df485ad")
      assert conn.app == "jira-software-cloud"
      assert conn.id == "025841e4-b17e-86f2-b9a4-6ef54df485ad"
      assert conn.label == nil
      assert conn.metadata == %{}
    end

    test "accepts an optional label and metadata" do
      conn = Connection.new("slack", "abc", label: "work slack", metadata: %{team: "eng"})
      assert conn.label == "work slack"
      assert conn.metadata == %{team: "eng"}
    end

    test "stringifies the id" do
      assert Connection.new("slack", 99).id == "99"
    end
  end

  describe "resolve!/1" do
    test "passes a struct through unchanged" do
      conn = Connection.new("google-drive", "456")
      assert Connection.resolve!(conn) == conn
    end

    test "resolves a named connection from config" do
      conn = Connection.resolve!(:drive)
      assert conn.app == "google-drive"
      assert conn.id == "conn-drive-uuid"
      assert conn.label == "drive"
    end

    test "raises a message that names the known connections" do
      assert_raise ArgumentError, ~r/no connection named :nonexistent/, fn ->
        Connection.resolve!(:nonexistent)
      end

      assert_raise ArgumentError, ~r/:drive/, fn ->
        Connection.resolve!(:nonexistent)
      end
    end
  end
end

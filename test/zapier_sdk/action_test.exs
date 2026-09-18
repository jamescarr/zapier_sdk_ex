defmodule ZapierSDK.ActionTest do
  use ExUnit.Case, async: true

  alias ZapierSDK.Action

  describe "constructors" do
    test "build actions of the matching type" do
      assert %Action{type: :search, name: "file_v2"} = Action.search("file_v2")
      assert %Action{type: :read, name: "rowList"} = Action.read("rowList")
      assert %Action{type: :write, name: "channel_message"} = Action.write("channel_message")
    end

    test "default to empty inputs" do
      assert Action.search("file_v2").inputs == %{}
    end
  end

  describe "type_to_api/1" do
    test "renders every supported type" do
      for type <- Action.types() do
        assert Action.type_to_api(type) == Atom.to_string(type)
      end
    end

    test "raises on an unknown type rather than sending it to the API" do
      assert_raise ArgumentError, ~r/unknown action type :sarch/, fn ->
        Action.type_to_api(:sarch)
      end
    end
  end
end

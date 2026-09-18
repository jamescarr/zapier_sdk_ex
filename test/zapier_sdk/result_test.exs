defmodule ZapierSDK.ResultTest do
  use ExUnit.Case, async: true

  alias ZapierSDK.Result

  describe "new/2" do
    test "creates result from data" do
      result = Result.new([%{"a" => 1}, %{"b" => 2}], elapsed_ms: 150)
      assert result.count == 2
      assert result.elapsed_ms == 150
    end
  end

  describe "first/1" do
    test "returns first element" do
      result = Result.new([%{"first" => true}, %{"first" => false}])
      assert Result.first(result) == %{"first" => true}
    end

    test "returns nil for empty result" do
      assert Result.first(Result.new([])) == nil
    end
  end

  describe "empty?/1" do
    test "returns true for empty" do
      assert Result.empty?(Result.new([]))
    end

    test "returns false for non-empty" do
      refute Result.empty?(Result.new([%{"a" => 1}]))
    end
  end

  describe "Enumerable" do
    test "supports Enum functions" do
      result = Result.new([%{"n" => 1}, %{"n" => 2}, %{"n" => 3}])
      assert Enum.count(result) == 3
      assert Enum.map(result, & &1["n"]) == [1, 2, 3]
    end

    test "supports member?" do
      item = %{"n" => 1}
      result = Result.new([item])
      assert Enum.member?(result, item)
      refute Enum.member?(result, %{"n" => 99})
    end
  end
end

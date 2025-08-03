defmodule Parrot.Sip.BranchTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.Branch

  describe "generate/0" do
    test "generates RFC 3261 compliant branch parameters" do
      branch = Branch.generate()
      assert is_binary(branch)
      assert String.starts_with?(branch, "z9hG4bK")
      assert String.length(branch) > 10
    end

    test "generates unique branch parameters" do
      branches = for _ <- 1..100, do: Branch.generate()
      unique_branches = Enum.uniq(branches)
      assert length(unique_branches) == 100
    end
  end

  describe "generate_for_message/5" do
    test "generates deterministic branch based on message properties" do
      # Same inputs should produce the same branch
      branch1 =
        Branch.generate_for_message(
          :invite,
          "sip:alice@example.com",
          "123",
          nil,
          "call123@example.com"
        )

      branch2 =
        Branch.generate_for_message(
          :invite,
          "sip:alice@example.com",
          "123",
          nil,
          "call123@example.com"
        )

      assert branch1 == branch2

      # Different inputs should produce different branches
      branch3 =
        Branch.generate_for_message(
          :register,
          "sip:alice@example.com",
          "123",
          nil,
          "call123@example.com"
        )

      branch4 =
        Branch.generate_for_message(
          :invite,
          "sip:bob@example.com",
          "123",
          nil,
          "call123@example.com"
        )

      branch5 =
        Branch.generate_for_message(
          :invite,
          "sip:alice@example.com",
          "456",
          nil,
          "call123@example.com"
        )

      branch6 =
        Branch.generate_for_message(
          :invite,
          "sip:alice@example.com",
          "123",
          "456",
          "call123@example.com"
        )

      branch7 =
        Branch.generate_for_message(
          :invite,
          "sip:alice@example.com",
          "123",
          nil,
          "call456@example.com"
        )

      branches = [branch1, branch3, branch4, branch5, branch6, branch7]
      unique_branches = Enum.uniq(branches)
      assert length(unique_branches) == 6
    end

    test "generated branch starts with RFC 3261 magic cookie" do
      branch =
        Branch.generate_for_message(
          :invite,
          "sip:alice@example.com",
          "123",
          nil,
          "call123@example.com"
        )

      assert String.starts_with?(branch, "z9hG4bK")
    end
  end

  describe "is_rfc3261_compliant?/1" do
    test "returns true for RFC 3261 compliant branches" do
      assert Branch.is_rfc3261_compliant?("z9hG4bKabc123")
      assert Branch.is_rfc3261_compliant?("z9hG4bK" <> String.duplicate("a", 100))
    end

    test "returns false for non-compliant branches" do
      assert not Branch.is_rfc3261_compliant?("abc123")
      # wrong case
      assert not Branch.is_rfc3261_compliant?("Z9hG4bKabc123")
      # wrong case
      assert not Branch.is_rfc3261_compliant?("z9hG4bk123")
    end

    test "returns false for non-string inputs" do
      assert not Branch.is_rfc3261_compliant?(123)
      assert not Branch.is_rfc3261_compliant?(nil)
      assert not Branch.is_rfc3261_compliant?([])
    end
  end

  describe "ensure_rfc3261_compliance/1" do
    test "leaves compliant branches unchanged" do
      branch = "z9hG4bKabc123"
      assert Branch.ensure_rfc3261_compliance(branch) == branch
    end

    test "adds magic cookie to non-compliant branches" do
      branch = "abc123"
      assert Branch.ensure_rfc3261_compliance(branch) == "z9hG4bKabc123"
    end
  end

  describe "transaction_id/1" do
    test "removes magic cookie from compliant branches" do
      assert Branch.transaction_id("z9hG4bKabc123") == "abc123"
    end

    test "returns original string for non-compliant branches" do
      assert Branch.transaction_id("abc123") == "abc123"
    end
  end

  describe "same_transaction?/2" do
    test "returns true for branches with same transaction ID" do
      assert Branch.same_transaction?("z9hG4bKabc123", "z9hG4bKabc123")
      assert Branch.same_transaction?("z9hG4bKabc123", "abc123")
      assert Branch.same_transaction?("abc123", "z9hG4bKabc123")
    end

    test "returns false for branches with different transaction IDs" do
      assert not Branch.same_transaction?("z9hG4bKabc123", "z9hG4bKdef456")
      assert not Branch.same_transaction?("z9hG4bKabc123", "def456")
    end

    test "returns false for invalid inputs" do
      assert not Branch.same_transaction?("z9hG4bKabc123", nil)
      assert not Branch.same_transaction?(nil, "z9hG4bKabc123")
      assert not Branch.same_transaction?(123, "z9hG4bKabc123")
    end
  end
end

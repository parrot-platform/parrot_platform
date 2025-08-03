defmodule Parrot.Sip.MethodSetTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.MethodSet

  describe "new/0" do
    test "creates an empty method set" do
      set = MethodSet.new()
      assert MethodSet.size(set) == 0
      assert Enum.to_list(set) == []
    end
  end

  describe "new/1" do
    test "creates a method set from a list of methods" do
      set = MethodSet.new([:invite, :ack, :bye])
      assert MethodSet.size(set) == 3
      assert Enum.sort(Enum.to_list(set)) == [:ack, :bye, :invite]
    end

    test "creates a method set from a list of method strings" do
      set = MethodSet.new(["INVITE", "ACK", "BYE"])
      assert MethodSet.size(set) == 3
      assert Enum.sort(Enum.to_list(set)) == [:ack, :bye, :invite]
    end

    test "handles mixed case in method strings" do
      set = MethodSet.new(["invite", "Ack", "BYE"])
      assert MethodSet.size(set) == 3
      assert Enum.sort(Enum.to_list(set)) == [:ack, :bye, :invite]
    end

    test "creates a set with no duplicates" do
      set = MethodSet.new([:invite, :ack, :invite, :bye, :ack])
      assert MethodSet.size(set) == 3
      assert Enum.sort(Enum.to_list(set)) == [:ack, :bye, :invite]
    end
  end

  describe "standard_methods/0" do
    test "returns a set of all standard SIP methods" do
      set = MethodSet.standard_methods()
      assert MethodSet.member?(set, :invite)
      assert MethodSet.member?(set, :ack)
      assert MethodSet.member?(set, :bye)
      assert MethodSet.member?(set, :options)
      assert MethodSet.member?(set, :cancel)
      assert MethodSet.member?(set, :register)
      # At least 10 standard methods
      assert MethodSet.size(set) >= 10
    end
  end

  describe "dialog_methods/0" do
    test "returns a set with the basic dialog methods" do
      set = MethodSet.dialog_methods()
      assert MethodSet.size(set) == 3
      assert MethodSet.member?(set, :invite)
      assert MethodSet.member?(set, :ack)
      assert MethodSet.member?(set, :bye)
      assert not MethodSet.member?(set, :options)
    end
  end

  describe "put/2" do
    test "adds a method to the set" do
      set = MethodSet.new([:invite, :ack])
      new_set = MethodSet.put(set, :bye)

      assert MethodSet.size(new_set) == 3
      assert MethodSet.member?(new_set, :bye)
    end

    test "accepts method as string" do
      set = MethodSet.new([:invite, :ack])
      new_set = MethodSet.put(set, "BYE")

      assert MethodSet.size(new_set) == 3
      assert MethodSet.member?(new_set, :bye)
    end

    test "doesn't add duplicate methods" do
      set = MethodSet.new([:invite, :ack, :bye])
      new_set = MethodSet.put(set, :bye)

      assert MethodSet.size(new_set) == 3
      assert new_set == set
    end
  end

  describe "put_all/2" do
    test "adds multiple methods to the set" do
      set = MethodSet.new([:invite])
      new_set = MethodSet.put_all(set, [:ack, :bye])

      assert MethodSet.size(new_set) == 3
      assert MethodSet.member?(new_set, :invite)
      assert MethodSet.member?(new_set, :ack)
      assert MethodSet.member?(new_set, :bye)
    end

    test "accepts methods as strings" do
      set = MethodSet.new([:invite])
      new_set = MethodSet.put_all(set, ["ACK", "BYE"])

      assert MethodSet.size(new_set) == 3
      assert MethodSet.member?(new_set, :ack)
      assert MethodSet.member?(new_set, :bye)
    end

    test "doesn't add duplicate methods" do
      set = MethodSet.new([:invite, :ack])
      new_set = MethodSet.put_all(set, [:invite, :bye])

      assert MethodSet.size(new_set) == 3
      assert MethodSet.member?(new_set, :bye)
    end
  end

  describe "delete/2" do
    test "removes a method from the set" do
      set = MethodSet.new([:invite, :ack, :bye])
      new_set = MethodSet.delete(set, :ack)

      assert MethodSet.size(new_set) == 2
      assert not MethodSet.member?(new_set, :ack)
      assert MethodSet.member?(new_set, :invite)
      assert MethodSet.member?(new_set, :bye)
    end

    test "accepts method as string" do
      set = MethodSet.new([:invite, :ack, :bye])
      new_set = MethodSet.delete(set, "ACK")

      assert MethodSet.size(new_set) == 2
      assert not MethodSet.member?(new_set, :ack)
    end

    test "ignores removing methods not in the set" do
      set = MethodSet.new([:invite, :ack])
      new_set = MethodSet.delete(set, :bye)

      assert MethodSet.size(new_set) == 2
      assert new_set == set
    end
  end

  describe "member?/2" do
    test "returns true for methods in the set" do
      set = MethodSet.new([:invite, :ack, :bye])

      assert MethodSet.member?(set, :invite)
      assert MethodSet.member?(set, :ack)
      assert MethodSet.member?(set, :bye)
    end

    test "accepts method as string" do
      set = MethodSet.new([:invite, :ack, :bye])

      assert MethodSet.member?(set, "INVITE")
      assert MethodSet.member?(set, "invite")
    end

    test "returns false for methods not in the set" do
      set = MethodSet.new([:invite, :ack])

      assert not MethodSet.member?(set, :bye)
      assert not MethodSet.member?(set, :cancel)
    end
  end

  describe "union/2" do
    test "returns the union of two method sets" do
      set1 = MethodSet.new([:invite, :ack])
      set2 = MethodSet.new([:bye, :cancel])

      union = MethodSet.union(set1, set2)

      assert MethodSet.size(union) == 4
      assert MethodSet.member?(union, :invite)
      assert MethodSet.member?(union, :ack)
      assert MethodSet.member?(union, :bye)
      assert MethodSet.member?(union, :cancel)
    end

    test "handles overlapping sets" do
      set1 = MethodSet.new([:invite, :ack, :bye])
      set2 = MethodSet.new([:bye, :cancel, :invite])

      union = MethodSet.union(set1, set2)

      assert MethodSet.size(union) == 4
      assert MethodSet.to_list(union) == [:ack, :bye, :cancel, :invite]
    end
  end

  describe "intersection/2" do
    test "returns the intersection of two method sets" do
      set1 = MethodSet.new([:invite, :ack, :bye])
      set2 = MethodSet.new([:bye, :cancel, :invite])

      intersection = MethodSet.intersection(set1, set2)

      assert MethodSet.size(intersection) == 2
      assert MethodSet.member?(intersection, :invite)
      assert MethodSet.member?(intersection, :bye)
      assert not MethodSet.member?(intersection, :ack)
      assert not MethodSet.member?(intersection, :cancel)
    end

    test "returns empty set when no common methods" do
      set1 = MethodSet.new([:invite, :ack])
      set2 = MethodSet.new([:bye, :cancel])

      intersection = MethodSet.intersection(set1, set2)

      assert MethodSet.size(intersection) == 0
      assert Enum.to_list(intersection) == []
    end
  end

  describe "difference/2" do
    test "returns the difference of two method sets" do
      set1 = MethodSet.new([:invite, :ack, :bye])
      set2 = MethodSet.new([:bye, :cancel])

      difference = MethodSet.difference(set1, set2)

      assert MethodSet.size(difference) == 2
      assert MethodSet.member?(difference, :invite)
      assert MethodSet.member?(difference, :ack)
      assert not MethodSet.member?(difference, :bye)
    end

    test "returns the original set when no common methods" do
      set1 = MethodSet.new([:invite, :ack])
      set2 = MethodSet.new([:bye, :cancel])

      difference = MethodSet.difference(set1, set2)

      assert difference == set1
    end
  end

  describe "to_list/1" do
    test "converts a method set to a sorted list" do
      set = MethodSet.new([:cancel, :invite, :ack, :bye])

      assert MethodSet.to_list(set) == [:ack, :bye, :cancel, :invite]
    end

    test "returns an empty list for an empty set" do
      set = MethodSet.new()

      assert MethodSet.to_list(set) == []
    end
  end

  describe "to_allow_string/1" do
    test "formats a method set as an Allow header value" do
      set = MethodSet.new([:invite, :ack, :bye])

      assert MethodSet.to_allow_string(set) == "ACK, BYE, INVITE"
    end

    test "returns an empty string for an empty set" do
      set = MethodSet.new()

      assert MethodSet.to_allow_string(set) == ""
    end
  end

  describe "from_allow_string/1" do
    test "parses an Allow header value into a method set" do
      set = MethodSet.from_allow_string("INVITE, ACK, BYE")

      assert MethodSet.size(set) == 3
      assert MethodSet.member?(set, :invite)
      assert MethodSet.member?(set, :ack)
      assert MethodSet.member?(set, :bye)
    end

    test "handles whitespace and case variations" do
      set = MethodSet.from_allow_string(" INVITE,ack, Bye ")

      assert MethodSet.size(set) == 3
      assert MethodSet.member?(set, :invite)
      assert MethodSet.member?(set, :ack)
      assert MethodSet.member?(set, :bye)
    end

    test "returns an empty set for an empty string" do
      set = MethodSet.from_allow_string("")

      assert MethodSet.size(set) == 0
    end
  end

  describe "size/1" do
    test "returns the number of methods in the set" do
      assert MethodSet.size(MethodSet.new()) == 0
      assert MethodSet.size(MethodSet.new([:invite])) == 1
      assert MethodSet.size(MethodSet.new([:invite, :ack, :bye])) == 3
    end
  end

  describe "Enumerable implementation" do
    test "count/1 returns the correct count" do
      set = MethodSet.new([:invite, :ack, :bye])
      assert Enum.count(set) == 3
    end

    test "member?/2 checks membership correctly" do
      set = MethodSet.new([:invite, :ack, :bye])
      assert Enum.member?(set, :invite)
      assert not Enum.member?(set, :register)
    end

    test "reduce/3 allows enumeration" do
      set = MethodSet.new([:invite, :ack, :bye])
      methods = Enum.into(set, [])
      assert Enum.sort(methods) == [:ack, :bye, :invite]
    end
  end
end

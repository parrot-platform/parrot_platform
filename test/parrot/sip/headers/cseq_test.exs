defmodule Parrot.Sip.Headers.CSeqTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing CSeq headers" do
    test "parses CSeq header" do
      header_value = "314159 INVITE"

      cseq = Headers.CSeq.parse(header_value)

      assert cseq.number == 314_159
      assert cseq.method == :invite

      assert Headers.CSeq.format(cseq) == header_value
    end

    test "parses CSeq header with different methods" do
      test_cases = [
        {"1 INVITE", 1, :invite},
        {"2 ACK", 2, :ack},
        {"3 BYE", 3, :bye},
        {"4 CANCEL", 4, :cancel},
        {"5 REGISTER", 5, :register},
        {"6 OPTIONS", 6, :options},
        {"7 SUBSCRIBE", 7, :subscribe},
        {"8 NOTIFY", 8, :notify},
        {"9 REFER", 9, :refer},
        {"10 MESSAGE", 10, :message},
        {"11 INFO", 11, :info},
        {"12 PRACK", 12, :prack},
        {"13 UPDATE", 13, :update}
      ]

      for {header_value, expected_number, expected_method} <- test_cases do
        cseq = Headers.CSeq.parse(header_value)
        assert cseq.number == expected_number
        assert cseq.method == expected_method
        assert Headers.CSeq.format(cseq) == header_value
      end
    end
  end

  describe "creating CSeq headers" do
    test "creates CSeq header" do
      cseq = Headers.CSeq.new(314_159, :invite)

      assert cseq.number == 314_159
      assert cseq.method == :invite

      assert Headers.CSeq.format(cseq) == "314159 INVITE"
    end
  end
end

defmodule Parrot.Media.RtpPacket do
  @moduledoc """
  RTP packet creation and parsing.

  RTP packet format:
   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |V=2|P|X|  CC   |M|     PT      |       sequence number         |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                           timestamp                           |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |           synchronization source (SSRC) identifier            |
  +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
  """

  import Bitwise

  @rtp_version 2
  # G.711 μ-law
  @payload_type_pcmu 0

  defstruct version: @rtp_version,
            padding: false,
            extension: false,
            # CSRC count
            cc: 0,
            marker: false,
            payload_type: @payload_type_pcmu,
            sequence_number: 0,
            timestamp: 0,
            ssrc: 0,
            payload: <<>>

  @doc """
  Creates a new RTP packet with the given payload.
  """
  def new(payload, opts \\ []) do
    %__MODULE__{
      payload_type: Keyword.get(opts, :payload_type, @payload_type_pcmu),
      sequence_number: Keyword.get(opts, :sequence_number, 0),
      timestamp: Keyword.get(opts, :timestamp, 0),
      ssrc: Keyword.get(opts, :ssrc, :rand.uniform(0xFFFFFFFF)),
      marker: Keyword.get(opts, :marker, false),
      payload: payload
    }
  end

  @doc """
  Encodes an RTP packet to binary format.
  """
  def encode(%__MODULE__{} = packet) do
    # First byte: V(2), P(1), X(1), CC(4)
    byte1 =
      @rtp_version <<< 6 |||
        bool_to_bit(packet.padding) <<< 5 |||
        bool_to_bit(packet.extension) <<< 4 |||
        (packet.cc &&& 0x0F)

    # Second byte: M(1), PT(7)
    byte2 = bool_to_bit(packet.marker) <<< 7 ||| (packet.payload_type &&& 0x7F)

    # Build the header
    header = <<
      byte1::8,
      byte2::8,
      packet.sequence_number::16,
      packet.timestamp::32,
      packet.ssrc::32
    >>

    # Combine header and payload
    header <> packet.payload
  end

  @doc """
  Decodes a binary RTP packet.
  """
  def decode(<<
        v::2,
        p::1,
        x::1,
        cc::4,
        m::1,
        pt::7,
        seq::16,
        ts::32,
        ssrc::32,
        rest::binary
      >>) do
    # Skip CSRC identifiers if present
    csrc_size = cc * 4
    <<_csrc::binary-size(csrc_size), payload::binary>> = rest

    {:ok,
     %__MODULE__{
       version: v,
       padding: p == 1,
       extension: x == 1,
       cc: cc,
       marker: m == 1,
       payload_type: pt,
       sequence_number: seq,
       timestamp: ts,
       ssrc: ssrc,
       payload: payload
     }}
  end

  def decode(_), do: {:error, :invalid_packet}

  defp bool_to_bit(true), do: 1
  defp bool_to_bit(false), do: 0
end

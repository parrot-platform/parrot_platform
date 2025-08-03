defmodule Parrot.Sip.Sdp do
  @moduledoc """
  Simple SDP parser for extracting media information.

  This is a basic implementation that extracts the essential
  information needed for RTP media sessions.
  """

  require Logger

  @type media_description :: %{
          type: :audio | :video,
          port: non_neg_integer(),
          protocol: String.t(),
          formats: [String.t()],
          attributes: map()
        }

  @type t :: %{
          version: String.t(),
          origin: String.t(),
          session_name: String.t(),
          connection:
            %{
              network_type: String.t(),
              address_type: String.t(),
              address: String.t()
            }
            | nil,
          media: [media_description()]
        }

  @doc """
  Parses an SDP body string.

  Returns `{:ok, sdp}` on success or `{:error, reason}` on failure.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(body) when is_binary(body) do
    lines = String.split(body, ~r/\r?\n/, trim: true)

    try do
      sdp = parse_lines(lines, %{media: []})
      {:ok, sdp}
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts the first audio media description from SDP.

  Returns `{:ok, {ip, port, payload_types}}` or `{:error, reason}`.
  """
  @spec get_audio_info(t()) ::
          {:ok, {String.t(), non_neg_integer(), [String.t()]}} | {:error, term()}
  def get_audio_info(sdp) do
    case find_audio_media(sdp) do
      nil ->
        {:error, :no_audio_media}

      audio ->
        connection_ip = get_connection_address(sdp)
        {:ok, {connection_ip, audio.port, audio.formats}}
    end
  end

  # Private functions

  defp parse_lines([], sdp), do: sdp

  defp parse_lines([line | rest], sdp) do
    case parse_line(line) do
      {:version, v} ->
        parse_lines(rest, Map.put(sdp, :version, v))

      {:origin, o} ->
        parse_lines(rest, Map.put(sdp, :origin, o))

      {:session_name, s} ->
        parse_lines(rest, Map.put(sdp, :session_name, s))

      {:connection, c} ->
        parse_lines(rest, Map.put(sdp, :connection, c))

      {:media, m} ->
        {media_attrs, remaining} = parse_media_attributes(rest, m, [])
        m_with_attrs = Map.put(m, :attributes, parse_attributes(media_attrs))
        parse_lines(remaining, update_in(sdp, [:media], &(&1 ++ [m_with_attrs])))

      {:attribute, _} ->
        # Session-level attribute, ignore for now
        parse_lines(rest, sdp)

      :ignore ->
        parse_lines(rest, sdp)
    end
  end

  defp parse_line("v=" <> version) do
    {:version, version}
  end

  defp parse_line("o=" <> origin) do
    {:origin, origin}
  end

  defp parse_line("s=" <> session_name) do
    {:session_name, session_name}
  end

  defp parse_line("c=" <> connection) do
    case String.split(connection, " ") do
      [network_type, address_type, address] ->
        {:connection,
         %{
           network_type: network_type,
           address_type: address_type,
           address: address
         }}

      _ ->
        :ignore
    end
  end

  defp parse_line("m=" <> media) do
    case String.split(media, " ") do
      [type, port, protocol | formats] ->
        {:media,
         %{
           type: String.to_atom(type),
           port: String.to_integer(port),
           protocol: protocol,
           formats: formats
         }}

      _ ->
        :ignore
    end
  end

  defp parse_line("a=" <> attribute) do
    {:attribute, attribute}
  end

  defp parse_line(_), do: :ignore

  defp parse_media_attributes([line | rest], media, attrs) do
    case line do
      "m=" <> _ ->
        # Start of new media section
        {attrs, [line | rest]}

      "a=" <> attr ->
        parse_media_attributes(rest, media, [attr | attrs])

      _ ->
        # Other lines are ignored within media section
        parse_media_attributes(rest, media, attrs)
    end
  end

  defp parse_media_attributes([], _media, attrs) do
    {attrs, []}
  end

  defp parse_attributes(attrs) do
    Enum.reduce(attrs, %{}, fn attr, acc ->
      case String.split(attr, ":", parts: 2) do
        [key, value] ->
          Map.put(acc, key, value)

        [key] ->
          Map.put(acc, key, true)
      end
    end)
  end

  defp find_audio_media(%{media: media}) do
    Enum.find(media, fn m -> m.type == :audio end)
  end

  defp get_connection_address(%{connection: %{address: addr}}), do: addr
  defp get_connection_address(_), do: "0.0.0.0"
end

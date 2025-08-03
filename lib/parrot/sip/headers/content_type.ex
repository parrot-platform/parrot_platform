defmodule Parrot.Sip.Headers.ContentType do
  @moduledoc """
  Module for working with SIP Content-Type headers as defined in RFC 3261 Section 20.15.

  The Content-Type header indicates the media type of the message body, providing 
  information about how to interpret the message body. It follows the MIME type format
  as specified in RFC 2045.

  Content-Type plays an important role in SIP messages:
  - Identifies the format of the message body (e.g., SDP, XML)
  - Allows proper parsing and rendering of the content
  - Facilitates content negotiation between endpoints
  - Enables support for multipart message bodies using the multipart/* type

  Common Content-Type values in SIP include:
  - application/sdp: Session Description Protocol used for media negotiation
  - application/pidf+xml: Presence Information Data Format
  - multipart/mixed: Multiple body parts with different content types

  References:
  - RFC 3261 Section 7.4.1: Header Field Format
  - RFC 3261 Section 20.15: Content-Type Header Field
  - RFC 2045: Multipurpose Internet Mail Extensions (MIME) Part One
  - RFC 3204: MIME media types for ISUP and QSIG Objects
  """

  defstruct [
    :type,
    :subtype,
    :parameters
  ]

  @type t :: %__MODULE__{
          type: String.t(),
          subtype: String.t(),
          parameters: map()
        }

  @doc """
  Creates a new Content-Type header.

  ## Examples

      iex> Parrot.Sip.Headers.ContentType.new("application", "sdp")
      %Parrot.Sip.Headers.ContentType{type: "application", subtype: "sdp", parameters: %{}}
      
      iex> Parrot.Sip.Headers.ContentType.new("multipart", "mixed", %{"boundary" => "boundary42"})
      %Parrot.Sip.Headers.ContentType{type: "multipart", subtype: "mixed", parameters: %{"boundary" => "boundary42"}}
  """
  @spec new(String.t(), String.t(), map()) :: t()
  def new(type, subtype, parameters \\ %{}) do
    %__MODULE__{
      type: type,
      subtype: subtype,
      parameters: parameters
    }
  end

  @doc """
  Parses a Content-Type header value.

  ## Examples

      iex> Parrot.Sip.Headers.ContentType.parse("application/sdp")
      %Parrot.Sip.Headers.ContentType{type: "application", subtype: "sdp", parameters: %{}}
      
      iex> Parrot.Sip.Headers.ContentType.parse("multipart/mixed; boundary=boundary42")
      %Parrot.Sip.Headers.ContentType{type: "multipart", subtype: "mixed", parameters: %{"boundary" => "boundary42"}}

  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    string = String.trim(string)

    # Split into media type and parameters
    {media_type, params_str} =
      case String.split(string, ";", parts: 2) do
        [media_type, params] -> {media_type, params}
        [media_type] -> {media_type, ""}
      end

    # Split media type into type and subtype
    [type, subtype] = String.split(media_type, "/", parts: 2)

    # Parse parameters
    parameters =
      if params_str != "" do
        params_str
        |> String.split(";")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn param ->
          case String.split(param, "=", parts: 2) do
            [name, value] -> {name, value}
            [name] -> {name, ""}
          end
        end)
        |> Enum.into(%{})
      else
        %{}
      end

    %__MODULE__{
      type: type,
      subtype: subtype,
      parameters: parameters
    }
  end

  @doc """
  Formats a Content-Type header value.

  ## Examples

      iex> content_type = %Parrot.Sip.Headers.ContentType{type: "application", subtype: "sdp", parameters: %{}}
      iex> Parrot.Sip.Headers.ContentType.format(content_type)
      "application/sdp"
      
      iex> content_type = %Parrot.Sip.Headers.ContentType{type: "multipart", subtype: "mixed", parameters: %{"boundary" => "boundary42"}}
      iex> Parrot.Sip.Headers.ContentType.format(content_type)
      "multipart/mixed; boundary=boundary42"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = content_type) do
    media_type = "#{content_type.type}/#{content_type.subtype}"

    if map_size(content_type.parameters) == 0 do
      media_type
    else
      params_str =
        content_type.parameters
        |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
        |> Enum.join("; ")

      "#{media_type}; #{params_str}"
    end
  end

  @doc """
  Extracts the media type from a Content-Type header.

  ## Examples

      iex> content_type = %Parrot.Sip.Headers.ContentType{type: "application", subtype: "sdp", parameters: %{}}
      iex> Parrot.Sip.Headers.ContentType.media_type(content_type)
      "application/sdp"

  """
  @spec media_type(t()) :: String.t()
  def media_type(%__MODULE__{} = content_type) do
    "#{content_type.type}/#{content_type.subtype}"
  end

  @doc """
  Extracts parameters from a Content-Type header.

  ## Examples

      iex> content_type = %Parrot.Sip.Headers.ContentType{type: "multipart", subtype: "mixed", parameters: %{"boundary" => "boundary42"}}
      iex> Parrot.Sip.Headers.ContentType.parameters(content_type)
      %{"boundary" => "boundary42"}

  """
  @spec parameters(t()) :: map()
  def parameters(%__MODULE__{} = content_type) do
    content_type.parameters
  end

  @doc """
  Creates a Content-Type header value with parameters.

  ## Examples

      iex> Parrot.Sip.Headers.ContentType.create("multipart/mixed", %{"boundary" => "boundary42"})
      %Parrot.Sip.Headers.ContentType{type: "multipart", subtype: "mixed", parameters: %{"boundary" => "boundary42"}}
      
  """
  @spec create(String.t(), map()) :: t()
  def create(media_type, parameters \\ %{}) when is_binary(media_type) and is_map(parameters) do
    [type, subtype] = String.split(media_type, "/", parts: 2)
    new(type, subtype, parameters)
  end
end

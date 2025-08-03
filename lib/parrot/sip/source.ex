defmodule Parrot.Sip.Source do
  @moduledoc """
  SIP Source module.

  Represents the source of a SIP message, including local and remote addresses,
  transport, and source identifier.
  """

  @typedoc """
  Represents a SIP message source
  """
  @type t :: %__MODULE__{
          local: {:inet.ip_address(), :inet.port_number()},
          remote: {:inet.ip_address(), :inet.port_number()},
          transport: atom(),
          source_id: String.t() | nil
        }

  @type source_id :: {module(), term()}

  defstruct [:local, :remote, :transport, :source_id]

  @doc """
  Creates a new source struct.

  ## Parameters
  - `local`: Tuple containing local IP address and port
  - `remote`: Tuple containing remote IP address and port
  - `transport`: Transport protocol (e.g., `:udp`, `:tcp`, `:tls`)
  - `source_id`: Optional source identifier

  ## Returns
  - `t()`: A new source struct
  """
  @spec new(
          local :: {:inet.ip_address(), :inet.port_number()},
          remote :: {:inet.ip_address(), :inet.port_number()},
          transport :: atom(),
          source_id :: String.t() | nil
        ) :: t()
  def new(local, remote, transport, source_id \\ nil) do
    %__MODULE__{
      local: local,
      remote: remote,
      transport: transport,
      source_id: source_id
    }
  end

  @doc """
  Creates a source ID from a module and options.

  ## Parameters
  - `module`: The module associated with the source
  - `options`: Source-specific options

  ## Returns
  - `source_id()`: A source ID tuple
  """
  @spec make_source_id(module(), term()) :: source_id()
  def make_source_id(module, options) do
    {module, options}
  end

  @doc """
  Gets the local address from a source.

  ## Parameters
  - `source`: Source struct

  ## Returns
  - Tuple of {host, port}
  """
  @spec local(t()) :: {:inet.ip_address(), :inet.port_number()}
  def local(%__MODULE__{local: local}), do: local

  @doc """
  Gets the remote address from a source.

  ## Parameters
  - `source`: Source struct

  ## Returns
  - Tuple of {host, port}
  """
  @spec remote(t()) :: {:inet.ip_address(), :inet.port_number()}
  def remote(%__MODULE__{remote: remote}), do: remote

  @doc """
  Sends a response to a source.

  ## Parameters
  - `response`: SIP message containing a response
  - `message`: Original SIP message

  ## Returns
  - `:ok`: Response was sent successfully
  """
  @spec send_response(Parrot.Sip.Message.t(), Parrot.Sip.Message.t()) :: :ok
  def send_response(_response, _message) do
    # This is a callback that will be implemented by transport modules
    # For now, just return :ok as a placeholder
    :ok
  end
end

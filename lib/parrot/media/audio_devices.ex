defmodule Parrot.Media.AudioDevices do
  @moduledoc """
  Manages audio device discovery and selection for PortAudio integration.

  This module provides functions to list available audio devices, get default
  devices, and validate device IDs for use with Membrane's PortAudio plugin.

  ## Example

      iex> Parrot.Media.AudioDevices.list_devices()
      {:ok, [
        %{id: 0, name: "Built-in Microphone", type: :input, channels: 2},
        %{id: 1, name: "Built-in Output", type: :output, channels: 2}
      ]}
      
      iex> Parrot.Media.AudioDevices.get_default_input()
      {:ok, 0}
  """

  require Logger

  @type device_info :: %{
          id: non_neg_integer(),
          name: String.t(),
          type: :input | :output,
          channels: non_neg_integer()
        }

  @doc """
  Lists all available audio devices.

  NOTE: The current version of membrane_portaudio_plugin doesn't provide
  programmatic access to device enumeration. Use `print_devices/0` to 
  see available devices in the console.

  Returns a stub response for compatibility.
  """
  @spec list_devices() :: {:ok, [device_info()]} | {:error, term()}
  def list_devices do
    # Current membrane_portaudio_plugin only has print_devices() which outputs to stdout
    # For now, return empty list to avoid crashes
    Logger.warning(
      "Device enumeration not available. Use Membrane.PortAudio.print_devices() to see devices."
    )

    {:ok, []}
  end

  @doc """
  Prints available audio devices to console.

  This calls Membrane.PortAudio.print_devices() which outputs device
  information to stdout.
  """
  @spec print_devices() :: :ok
  def print_devices do
    try do
      Application.ensure_all_started(:membrane_portaudio_plugin)
      Membrane.PortAudio.print_devices()
    rescue
      e ->
        Logger.error("Failed to print devices: #{inspect(e)}")
        {:error, e}
    end
  end

  @doc """
  Gets the default input device ID.

  Since device enumeration is not available, this returns the typical
  default input device ID. You may need to adjust this based on your
  system configuration. Use `print_devices/0` to see actual device IDs.
  """
  @spec get_default_input() :: {:ok, non_neg_integer()} | {:error, term()}
  def get_default_input do
    # Based on common PortAudio behavior, default input is usually ID 0 or 1
    # User should verify with print_devices()
    {:ok, 1}
  end

  @doc """
  Gets the default output device ID.

  Since device enumeration is not available, this returns the typical
  default output device ID. You may need to adjust this based on your
  system configuration. Use `print_devices/0` to see actual device IDs.
  """
  @spec get_default_output() :: {:ok, non_neg_integer()} | {:error, term()}
  def get_default_output do
    # Based on common PortAudio behavior, default output is usually ID 2
    # User should verify with print_devices()
    {:ok, 2}
  end

  @doc """
  Validates if a device ID exists and matches the expected type.

  Since device enumeration is not available, this performs basic validation
  based on common device ID patterns. Use `print_devices/0` to verify actual
  device IDs and types on your system.

  ## Parameters

    * `device_id` - The device ID to validate
    * `expected_type` - Either `:input` or `:output`

  ## Returns

    * `:ok` if the device ID is in a reasonable range
    * `{:error, reason}` otherwise
  """
  @spec validate_device(non_neg_integer(), :input | :output) :: :ok | {:error, term()}
  def validate_device(device_id, _expected_type) when is_integer(device_id) and device_id >= 0 do
    # Without enumeration, we can only do basic validation
    # Assume device IDs 0-10 are reasonable
    if device_id <= 10 do
      :ok
    else
      {:error, :device_id_out_of_range}
    end
  end

  def validate_device(_device_id, _expected_type) do
    {:error, :invalid_device_id}
  end

  @doc """
  Gets device information by ID.

  Since device enumeration is not available, this returns a stub response.
  Use `print_devices/0` to see actual device information.
  """
  @spec get_device_info(non_neg_integer()) :: {:ok, device_info()} | {:error, term()}
  def get_device_info(device_id) when is_integer(device_id) and device_id >= 0 do
    # Return stub info since we can't enumerate
    {:ok,
     %{
       id: device_id,
       name: "Device #{device_id}",
       type: if(device_id < 2, do: :input, else: :output),
       channels: 2
     }}
  end

  def get_device_info(_device_id) do
    {:error, :invalid_device_id}
  end
end

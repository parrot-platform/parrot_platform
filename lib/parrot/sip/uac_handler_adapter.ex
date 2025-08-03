defmodule Parrot.Sip.UacHandlerAdapter do
  @moduledoc """
  Adapter between the high-level UacHandler API and the low-level UAC callback mechanism.

  This module creates callback functions that bridge the low-level UAC transaction
  results to the high-level UacHandler behaviour callbacks. It handles:
  - Routing responses to appropriate handler callbacks based on status code
  - Managing handler state across callbacks
  - Processing special return values (ACK sending, redirects)
  - Error handling and propagation
  """

  alias Parrot.Sip.{Message, UAC, Uri}
  alias Parrot.Sip.Headers.{Contact, CSeq}
  require Logger

  @type handler_state :: %{
          handler_module: module(),
          handler_state: term(),
          dialog_id: term() | nil,
          original_request: Message.t() | nil
        }

  @doc """
  Creates a UAC callback function that adapts responses to UacHandler callbacks.

  ## Parameters
  - `handler_module` - Module implementing Parrot.UacHandler behaviour
  - `handler_init_args` - Arguments to pass to handler's init/1 callback

  ## Returns
  A callback function suitable for use with Parrot.Sip.UAC.request/3
  """
  @spec create_callback(module(), term()) :: UAC.callback()
  def create_callback(handler_module, handler_init_args) do
    # Initialize the handler
    case handler_module.init(handler_init_args) do
      {:ok, initial_state} ->
        # Create the adapter state
        adapter_state = %{
          handler_module: handler_module,
          handler_state: initial_state,
          dialog_id: nil,
          original_request: nil
        }

        # Return the callback function
        fn result -> handle_uac_result(result, adapter_state) end

      {:stop, reason} ->
        # Handler failed to initialize
        fn _result ->
          Logger.error("UAC handler failed to initialize: #{inspect(reason)}")
          {:stop, reason}
        end
    end
  end

  @doc """
  Creates a UAC callback with an already-initialized handler state.

  ## Parameters
  - `handler_module` - Module implementing Parrot.UacHandler behaviour  
  - `handler_state` - Pre-initialized handler state
  - `opts` - Options including :dialog_id, :original_request

  ## Returns
  A callback function suitable for use with Parrot.Sip.UAC.request/3
  """
  @spec create_callback_with_state(module(), term(), keyword()) :: UAC.callback()
  def create_callback_with_state(handler_module, handler_state, opts \\ []) do
    adapter_state = %{
      handler_module: handler_module,
      handler_state: handler_state,
      dialog_id: Keyword.get(opts, :dialog_id),
      original_request: Keyword.get(opts, :original_request)
    }

    fn result -> handle_uac_result(result, adapter_state) end
  end

  # Private functions

  defp handle_uac_result({:response, %Message{type: :response} = response}, adapter_state) do
    %{handler_module: handler_module, handler_state: handler_state} = adapter_state

    # Route to appropriate handler based on status code
    handler_result =
      case response.status_code do
        status when status >= 100 and status < 200 ->
          handler_module.handle_provisional(response, handler_state)

        status when status >= 200 and status < 300 ->
          handle_success_response(response, adapter_state)

        status when status >= 300 and status < 400 ->
          handler_module.handle_redirect(response, handler_state)

        status when status >= 400 and status < 500 ->
          handler_module.handle_client_error(response, handler_state)

        status when status >= 500 and status < 600 ->
          handler_module.handle_server_error(response, handler_state)

        status when status >= 600 and status < 700 ->
          handler_module.handle_global_failure(response, handler_state)

        _ ->
          Logger.warning("Unknown status code: #{response.status_code}")
          {:ok, handler_state}
      end

    # Process the handler result
    process_handler_result(handler_result, response, adapter_state)
  end

  defp handle_uac_result({:error, error}, adapter_state) do
    %{handler_module: handler_module, handler_state: handler_state} = adapter_state

    case handler_module.handle_error(error, handler_state) do
      {:ok, new_state} ->
        {:ok, %{adapter_state | handler_state: new_state}}

      {:stop, reason, _new_state} ->
        {:stop, reason}

      other ->
        Logger.error("Invalid return from handle_error: #{inspect(other)}")
        {:stop, :invalid_return}
    end
  end

  defp handle_uac_result({:stop, reason}, _adapter_state) do
    Logger.debug("UAC transaction stopped: #{inspect(reason)}")
    {:stop, reason}
  end

  defp handle_uac_result({:message, msg}, adapter_state) do
    %{handler_module: handler_module, handler_state: handler_state} = adapter_state

    # Forward to handle_info
    case handler_module.handle_info(msg, handler_state) do
      {:noreply, new_state} ->
        {:ok, %{adapter_state | handler_state: new_state}}

      {:stop, reason, _new_state} ->
        {:stop, reason}

      other ->
        Logger.error("Invalid return from handle_info: #{inspect(other)}")
        {:stop, :invalid_return}
    end
  end

  defp handle_success_response(response, adapter_state) do
    %{
      handler_module: handler_module,
      handler_state: handler_state,
      original_request: original_request
    } = adapter_state

    result = handler_module.handle_success(response, handler_state)

    # Check if this is a 200 OK to INVITE that needs ACK
    if response.status_code == 200 and is_invite_response?(response, original_request) do
      handle_invite_success(result, response, adapter_state)
    else
      result
    end
  end

  defp is_invite_response?(response, original_request) do
    # Check CSeq header to see if this is response to INVITE
    case response.headers["cseq"] do
      %CSeq{method: "INVITE"} -> true
      %{"method" => "INVITE"} -> true
      cseq when is_binary(cseq) -> String.contains?(cseq, "INVITE")
      _ -> original_request && original_request.method == "INVITE"
    end
  end

  defp handle_invite_success(handler_result, response, adapter_state) do
    case handler_result do
      {:send_ack, ack_headers, ack_body, new_state} ->
        # Send custom ACK
        send_ack(response, ack_headers, ack_body)
        notify_call_established(adapter_state)
        {:ok, new_state}

      {:ok, new_state} ->
        # Send default ACK
        send_ack(response, %{}, "")
        notify_call_established(adapter_state)
        {:ok, new_state}

      other ->
        # For INVITE success, we still need to send ACK
        send_ack(response, %{}, "")
        notify_call_established(adapter_state)
        other
    end
  end

  defp send_ack(response, extra_headers, body) do
    # Build ACK request based on the 200 OK response
    ack_request = build_ack_request(response, extra_headers, body)
    
    # Allow for test mode where transport isn't started
    if Process.get(:uac_handler_test_mode) do
      send(Process.get(:uac_handler_test_pid), {:ack_sent, ack_request})
    else
      UAC.ack_request(ack_request)
    end
  end

  defp build_ack_request(response, extra_headers, body) do
    # Extract key headers from response
    to = response.headers["to"]
    from = response.headers["from"]
    call_id = response.headers["call-id"]
    
    # Get Contact from response for Request-URI
    request_uri = 
      case response.headers["contact"] do
        %Contact{uri: uri} -> uri
        contacts when is_list(contacts) -> 
          case List.first(contacts) do
            %Contact{uri: uri} -> uri
            _ -> extract_uri_from_to(to)
          end
        _ -> extract_uri_from_to(to)
      end

    # Build CSeq for ACK
    cseq = 
      case response.headers["cseq"] do
        %CSeq{number: seq} -> "#{seq} ACK"
        %{"number" => seq} -> "#{seq} ACK"
        cseq_str when is_binary(cseq_str) ->
          [seq | _] = String.split(cseq_str, " ")
          "#{seq} ACK"
      end

    # Build base headers
    base_headers = %{
      "to" => to,
      "from" => from,
      "call-id" => call_id,
      "cseq" => cseq,
      "via" => [],  # Will be added by transport
      "max-forwards" => "70",
      "content-length" => "#{byte_size(body)}"
    }

    # Add content-type if body present
    headers = 
      if body != "" do
        Map.put(base_headers, "content-type", Map.get(extra_headers, "content-type", "application/sdp"))
      else
        base_headers
      end

    # Merge with extra headers
    headers = Map.merge(headers, extra_headers)

    %Message{
      type: :request,
      method: "ACK",
      request_uri: request_uri,
      headers: headers,
      body: body
    }
  end

  defp extract_uri_from_to(to) when is_binary(to) do
    # Simple extraction of URI from To header
    case Regex.run(~r/<(.+)>/, to) do
      [_, uri] -> uri
      _ -> to
    end
  end

  defp extract_uri_from_to(%{uri: uri}), do: uri
  defp extract_uri_from_to(_), do: "sip:unknown@unknown"

  defp notify_call_established(%{handler_module: handler_module, handler_state: handler_state, dialog_id: dialog_id}) do
    if dialog_id do
      case handler_module.handle_call_established(dialog_id, handler_state) do
        {:ok, _new_state} -> :ok
        {:stop, _reason, _new_state} -> :ok
        _ -> :ok
      end
    end
  end

  defp process_handler_result({:ok, new_state}, _response, adapter_state) do
    {:ok, %{adapter_state | handler_state: new_state}}
  end

  defp process_handler_result({:stop, reason, _new_state}, _response, _adapter_state) do
    {:stop, reason}
  end

  defp process_handler_result({:send_ack, _headers, _body, new_state}, _response, adapter_state) do
    # ACK sending is handled in handle_invite_success
    {:ok, %{adapter_state | handler_state: new_state}}
  end

  defp process_handler_result({:follow_redirect, new_state}, response, adapter_state) do
    case extract_redirect_uri(response) do
      {:ok, redirect_uri} ->
        # Create new request to redirect URI
        original_request = adapter_state.original_request
        
        if original_request do
          # Update request URI
          new_request = %{original_request | request_uri: redirect_uri}
          
          # Create callback for redirect
          callback = create_callback_with_state(
            adapter_state.handler_module,
            new_state,
            dialog_id: adapter_state.dialog_id,
            original_request: new_request
          )
          
          # Send redirected request
          UAC.request(new_request, callback)
          {:ok, %{adapter_state | handler_state: new_state}}
        else
          Logger.error("Cannot follow redirect without original request")
          {:ok, %{adapter_state | handler_state: new_state}}
        end

      :error ->
        Logger.error("No Contact header in redirect response")
        {:ok, %{adapter_state | handler_state: new_state}}
    end
  end

  defp process_handler_result(other, _response, _adapter_state) do
    Logger.error("Invalid handler return value: #{inspect(other)}")
    {:stop, :invalid_return}
  end

  defp extract_redirect_uri(response) do
    case response.headers["contact"] do
      %Contact{uri: uri} -> {:ok, uri}
      contacts when is_list(contacts) ->
        case List.first(contacts) do
          %Contact{uri: uri} -> {:ok, uri}
          _ -> :error
        end
      contact when is_binary(contact) ->
        case Uri.parse(contact) do
          {:ok, uri} -> {:ok, uri}
          _ -> :error
        end
      _ -> :error
    end
  end
end
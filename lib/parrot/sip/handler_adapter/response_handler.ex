defmodule Parrot.Sip.HandlerAdapter.ResponseHandler do
  @moduledoc """
  Functions for handling SIP responses.

  This module handles the processing of responses from user handlers,
  including formatting and sending responses through the UAS layer.
  """

  require Logger
  alias Parrot.Sip.UAS

  @doc """
  Processes a response from the user handler and sends it via the UAS.

  This function takes a response tuple from the user handler, constructs a proper
  SIP response message, and sends it through the UAS layer.

  ## Parameters

    * `response` - The response tuple from the user handler
    * `uas` - The UAS object
    * `req_sip_msg` - The original request SIP message

  ## Returns

  The return value of `UAS.response/2`
  """
  def process_user_response({:respond, status, reason, headers, body}, uas, req_sip_msg) do
    Logger.debug("Processing user response: #{status} #{reason}")

    resp = UAS.make_reply(status, reason, uas, req_sip_msg)
    resp_with_headers = add_headers(resp, headers)
    resp_with_body = Parrot.Sip.Message.set_body(resp_with_headers, body)
    UAS.response(resp_with_body, uas)
  end

  def process_user_response({:proxy, uri}, uas, req_sip_msg) do
    Logger.info("Proxying request to #{uri}")
    proxy_request(uri, req_sip_msg, uas)
  end

  def process_user_response({:b2bua, _uri}, _uas, _req_sip_msg) do
    Logger.warning("B2BUA functionality has been removed")
    {:respond, 501, "Not Implemented", %{}, "", %{}}
  end

  def process_user_response(:noreply, _uas, _req_sip_msg) do
    Logger.debug("User handler returned :noreply.")
    :ok
  end

  def process_user_response(other, _uas, _req_sip_msg) do
    Logger.error("Unknown user response format: #{inspect(other)}")
    :ok
  end

  # Private functions

  defp add_headers(sip_msg, headers) do
    alias Parrot.Sip.HandlerAdapter.HeaderHandler
    HeaderHandler.add_headers(sip_msg, headers)
  end

  @doc """
  Proxies a SIP request to another URI.

  This function implements SIP proxying by forwarding the request to another URI
  and relaying the responses back to the original sender.

  For INVITE requests, it sends a provisional 100 Trying response first.

  ## Parameters

    * `uri` - The target URI to proxy the request to
    * `req_sip_msg` - The original SIP request message
    * `uas_obj` - The UAS object representing the original transaction

  ## Returns

  `:ok`
  """
  def proxy_request(uri, req_sip_msg, uas_obj) do
    # Ensure Transport and UAC are accessible or passed if these become instance methods
    if req_sip_msg.method == :invite do
      trying_resp = UAS.make_reply(100, "Trying", uas_obj, req_sip_msg)
      UAS.response(trying_resp, uas_obj)
    end

    forward_sip_msg = prepare_request_for_forwarding(req_sip_msg, uri)

    Parrot.Sip.UAC.request(forward_sip_msg, fn response ->
      case response do
        {:message, resp_sip_msg} ->
          forwarded_resp = prepare_response_for_forwarding(resp_sip_msg, req_sip_msg)
          UAS.response(forwarded_resp, uas_obj)

        {:stop, reason} ->
          Logger.warning("Proxy request failed: #{inspect(reason)}")
          error_resp = UAS.make_reply(500, "Proxy Error", uas_obj, req_sip_msg)
          UAS.response(error_resp, uas_obj)
      end
    end)

    :ok
  end

  @doc """
  Prepares a SIP request for forwarding to another URI.

  This function modifies a SIP request to prepare it for forwarding to a different
  destination. It:

  1. Updates the Request-URI to the target URI
  2. Decrements the Max-Forwards header to prevent infinite loops
  3. For INVITE requests, adds a Record-Route header to ensure responses are routed back
     through this proxy

  ## Parameters

    * `req_sip_msg` - The original SIP request message
    * `target_uri` - The target URI to forward the request to

  ## Returns

  The modified SIP request message ready for forwarding
  """
  def prepare_request_for_forwarding(req_sip_msg, target_uri) do
    # Set the new request URI
    req1 = %{req_sip_msg | request_uri: target_uri}

    # Decrement Max-Forwards
    max_forwards_val =
      case Parrot.Sip.Message.get_header(req1, "max-forwards") do
        nil -> Parrot.Sip.Headers.MaxForwards.default()
        val -> val
      end

    new_max_forwards =
      case Parrot.Sip.Headers.MaxForwards.decrement(max_forwards_val) do
        nil -> 0
        v -> v
      end

    req2 = Parrot.Sip.Message.set_header(req1, "max-forwards", new_max_forwards)

    # Add Record-Route if INVITE
    if req2.method == :invite do
      local_uri = Parrot.Sip.Transport.local_uri()
      record_route_hdr = Parrot.Sip.Headers.RecordRoute.new(local_uri)

      existing_routes =
        case Parrot.Sip.Message.get_header(req2, "record-route") do
          nil -> []
          r -> List.wrap(r)
        end

      Parrot.Sip.Message.set_header(req2, "record-route", [record_route_hdr | existing_routes])
    else
      req2
    end
  end

  @doc """
  Prepares a SIP response for forwarding to the original requester.

  This function takes a response received from the forwarded request and
  prepares it to be sent back to the original requester. It:

  1. Creates a new response to the original request with the same status code
  2. Copies the body from the received response
  3. Copies essential headers (Contact, Content-Type, Record-Route) from the received response

  ## Parameters

    * `resp_sip_msg` - The response received from the forwarded request
    * `orig_req_sip_msg` - The original request from the initial requester

  ## Returns

  The modified SIP response message ready to send back to the original requester
  """
  def prepare_response_for_forwarding(resp_sip_msg, orig_req_sip_msg) do
    status = resp_sip_msg.status_code
    reason = resp_sip_msg.reason_phrase || Parrot.Sip.Message.default_reason_phrase(status)
    base_resp = Parrot.Sip.Message.reply(orig_req_sip_msg, status, reason)
    resp_with_body = Parrot.Sip.Message.set_body(base_resp, resp_sip_msg.body)

    # Add other necessary headers
    headers_to_copy = ["contact", "content-type", "record-route"]

    Enum.reduce(headers_to_copy, resp_with_body, fn header_key, acc_resp ->
      case Parrot.Sip.Message.get_header(resp_sip_msg, header_key) do
        nil -> acc_resp
        value -> Parrot.Sip.Message.set_header(acc_resp, header_key, value)
      end
    end)
  end

end

defmodule Parrot.UasHandler do
  @moduledoc """
  Behaviour for implementing SIP User Agent Server (UAS) handlers in Parrot.

  The `Parrot.UasHandler` behaviour is the primary interface for building SIP server applications
  with the Parrot framework. By implementing this behaviour, you can handle incoming
  SIP requests and control how your application responds to various SIP methods.

  This behaviour follows the SIP protocol as defined in [RFC 3261](https://www.rfc-editor.org/rfc/rfc3261.html).

  ## Summary

  Parrot handles all the complex SIP protocol details (transactions, retransmissions,
  timers, dialog state) automatically. Your handler only needs to implement the business
  logic for each SIP method you want to support.

  ## Basic Usage

  ```elixir
  defmodule MyApp.UasHandler do
    use Parrot.UasHandler

    @impl true
    def init(args) do
      {:ok, %{calls: %{}}}
    end

    @impl true
    def handle_invite(message, state) do
      # Accept the call with 200 OK
      {:respond, 200, "OK", %{"content-type" => "application/sdp"}, sdp_body, state}
    end

    @impl true
    def handle_bye(_message, state) do
      # End the call
      {:respond, 200, "OK", %{}, "", state}
    end
  end
  ```

  ## State Management

  Each handler instance maintains its own state across the lifecycle of a dialog/call.
  The state is passed to each callback and the updated state from your response is
  preserved for subsequent callbacks.

  ## Response Types

  Handler callbacks can return several response types:

  - `{:respond, status, reason, headers, body, state}` - Send a SIP response
  - `{:proxy, uri, state}` - Proxy the request to another URI
  - `{:noreply, state}` - Don't send a response (e.g., for ACK)
  - `{:stop, reason, state}` - Stop the handler process

  ## Request Structure

  The `request` parameter passed to callbacks is a `Parrot.Sip.Message` struct containing:

  - `method` - The SIP method (atom like `:invite`, `:bye`, etc.)
  - `uri` - The Request-URI
  - `headers` - Map of SIP headers
  - `body` - Message body (typically SDP for INVITE)
  - `from` - Parsed From header
  - `to` - Parsed To header
  - `call_id` - Call-ID value
  - `cseq` - Parsed CSeq header

  ## Using the Behaviour

  When you `use Parrot.Handler`, default implementations are provided for all callbacks
  that return appropriate error responses (501 Not Implemented for most methods).
  You only need to override the methods your application supports.
  """

  require Logger

  @typedoc """
  A SIP request message.

  This is a `Parrot.Sip.Message` struct with at least these fields:
  - `method` - The SIP method as an atom (`:invite`, `:bye`, etc.)
  - `uri` - The Request-URI as a string
  - `headers` - Map of headers with lowercase string keys
  - `body` - Binary message body
  """
  @type request :: Parrot.Sip.Message.t()

  @typedoc """
  Possible responses from handler callbacks.

  - `{:respond, status, reason, headers, body, state}` - Send a SIP response
  - `{:proxy, uri, state}` - Proxy the request to another URI  
  - `{:noreply, state}` - Don't send a response
  - `{:stop, reason, state}` - Stop the handler process
  """
  @type response ::
          {:respond, status :: 100..699, reason :: String.t(), headers :: map(), body :: binary(),
           state}
          | {:proxy, uri :: String.t(), state}
          | {:noreply, state}
          | {:stop, reason :: term(), state}

  @typedoc "Handler state - can be any term"
  @type state :: term()

  @typedoc "Transaction process identifier"
  @type transaction :: pid()

  @typedoc "Dialog process identifier"
  @type dialog :: pid()

  # Core callbacks that most handlers need

  @doc """
  Initialize the handler state.

  Called when a new handler process is started. This happens when:
  - A new dialog is created (new INVITE)
  - A new out-of-dialog request arrives

  ## Parameters

  - `args` - Arguments passed when starting the handler

  ## Returns

  - `{:ok, state}` - Initialize with the given state
  - `{:stop, reason}` - Prevent the handler from starting

  ## Example

      @impl true
      def init(_args) do
        {:ok, %{
          calls: %{},
          config: Application.get_env(:my_app, :sip_config)
        }}
      end
  """
  @callback init(args :: term()) :: {:ok, state} | {:stop, reason :: term()}

  # Basic request handlers

  @doc """
  Handle INVITE requests.

  INVITE establishes a new session (call) as defined in [RFC 3261 Section 13](https://www.rfc-editor.org/rfc/rfc3261.html#section-13).
  This is typically where you:
  - Negotiate media capabilities via SDP ([RFC 3264](https://www.rfc-editor.org/rfc/rfc3264.html))
  - Decide whether to accept, reject, or redirect the call
  - Set up media handling

  ## Parameters

  - `request` - The INVITE request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.

  ## Examples

      @impl true
      def handle_invite(message, state) do
        cond do
          not authorized?(message) ->
            {:respond, 403, "Forbidden", %{}, "", state}
            
          busy?(state) ->
            {:respond, 486, "Busy Here", %{}, "", state}
            
          true ->
            sdp_answer = generate_sdp_answer(message.body)
            {:respond, 200, "OK", %{"content-type" => "application/sdp"}, sdp_answer, state}
        end
      end
  """
  @callback handle_invite(request, state) :: response

  @doc """
  Handle OPTIONS requests.

  OPTIONS is used to query the capabilities of a SIP endpoint as defined in
  [RFC 3261 Section 11](https://www.rfc-editor.org/rfc/rfc3261.html#section-11).
  Typically used for:
  - Keep-alive/ping functionality
  - Discovering supported methods and features
  - Pre-flight checks before sending INVITE

  ## Parameters

  - `request` - The OPTIONS request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.

  ## Example

      @impl true
      def handle_options(_message, state) do
        headers = %{
          "allow" => "INVITE, ACK, CANCEL, BYE, OPTIONS",
          "accept" => "application/sdp",
          "supported" => "replaces, timer"
        }
        {:respond, 200, "OK", headers, "", state}
      end
  """
  @callback handle_options(request, state) :: response

  @doc """
  Handle REGISTER requests.

  REGISTER is used to bind a user's address-of-record to one or more contact addresses
  as specified in [RFC 3261 Section 10](https://www.rfc-editor.org/rfc/rfc3261.html#section-10).
  This is typically used for:
  - User location registration
  - NAT keepalive
  - Presence updates

  ## Parameters

  - `request` - The REGISTER request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.

  ## Example

      @impl true
      def handle_register(message, state) do
        case authenticate(message) do
          :ok ->
            store_registration(message)
            {:respond, 200, "OK", %{}, "", state}
            
          :unauthorized ->
            challenge = generate_auth_challenge()
            {:respond, 401, "Unauthorized", %{"www-authenticate" => challenge}, "", state}
        end
      end
  """
  @callback handle_register(request, state) :: response

  @doc """
  Handle SUBSCRIBE requests.

  SUBSCRIBE creates a subscription for event notification as defined in
  [RFC 6665](https://www.rfc-editor.org/rfc/rfc6665.html). Common uses:
  - Presence (buddy lists) - [RFC 3856](https://www.rfc-editor.org/rfc/rfc3856.html)
  - Message waiting indication - [RFC 3842](https://www.rfc-editor.org/rfc/rfc3842.html)
  - Conference state - [RFC 4575](https://www.rfc-editor.org/rfc/rfc4575.html)
  - Dialog state - [RFC 4235](https://www.rfc-editor.org/rfc/rfc4235.html)

  ## Parameters

  - `request` - The SUBSCRIBE request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.

  ## Example

      @impl true  
      def handle_subscribe(message, state) do
        event = message.headers["event"]
        
        case event do
          "presence" ->
            # Create subscription and send immediate NOTIFY
            sub_id = create_subscription(message)
            send_notify(sub_id, current_presence_state())
            {:respond, 200, "OK", %{}, "", state}
            
          _ ->
            {:respond, 489, "Bad Event", %{}, "", state}
        end
      end
  """
  @callback handle_subscribe(request, state) :: response

  @doc """
  Handle NOTIFY requests.

  NOTIFY carries event notification data for active subscriptions as defined in
  [RFC 6665](https://www.rfc-editor.org/rfc/rfc6665.html).

  ## Parameters

  - `request` - The NOTIFY request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.
  """
  @callback handle_notify(request, state) :: response

  @doc """
  Handle PUBLISH requests.

  PUBLISH updates event state information as defined in
  [RFC 3903](https://www.rfc-editor.org/rfc/rfc3903.html). Often used for presence.

  ## Parameters

  - `request` - The PUBLISH request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.
  """
  @callback handle_publish(request, state) :: response

  @doc """
  Handle MESSAGE requests.

  MESSAGE sends instant messages using SIP as defined in
  [RFC 3428](https://www.rfc-editor.org/rfc/rfc3428.html). The body contains the message content.

  ## Parameters

  - `request` - The MESSAGE request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.

  ## Example

      @impl true
      def handle_message(message, state) do
        from = message.headers["from"]
        content_type = message.headers["content-type"]
        
        case content_type do
          "text/plain" ->
            deliver_message(from, message.body)
            {:respond, 200, "OK", %{}, "", state}
            
          _ ->
            {:respond, 415, "Unsupported Media Type", %{}, "", state}
        end
      end
  """
  @callback handle_message(request, state) :: response

  @doc """
  Handle BYE requests.

  BYE terminates an established session (hangs up a call) as defined in
  [RFC 3261 Section 15](https://www.rfc-editor.org/rfc/rfc3261.html#section-15).

  ## Parameters

  - `request` - The BYE request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.

  ## Example

      @impl true
      def handle_bye(message, state) do
        call_id = message.headers["call-id"]
        cleanup_call_resources(call_id)
        
        new_state = remove_call(state, call_id)
        {:respond, 200, "OK", %{}, "", new_state}
      end
  """
  @callback handle_bye(request, state) :: response

  @doc """
  Handle CANCEL requests.

  CANCEL cancels a pending INVITE transaction as defined in
  [RFC 3261 Section 9](https://www.rfc-editor.org/rfc/rfc3261.html#section-9).
  Note that CANCEL only affects the INVITE transaction - if the call is already
  established, use BYE instead.

  ## Parameters

  - `request` - The CANCEL request message  
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.
  """
  @callback handle_cancel(request, state) :: response

  @doc """
  Handle INFO requests.

  INFO sends application-level information during a session as defined in
  [RFC 6086](https://www.rfc-editor.org/rfc/rfc6086.html). Common uses:
  - DTMF digits (though [RFC 4733](https://www.rfc-editor.org/rfc/rfc4733.html) is preferred)
  - Video refresh requests
  - Call progress updates

  ## Parameters

  - `request` - The INFO request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple.
  """
  @callback handle_info(request, state) :: response

  @doc """
  Handle ACK requests.

  ACK confirms receipt of a final response to INVITE as defined in
  [RFC 3261 Section 13.2.2.4](https://www.rfc-editor.org/rfc/rfc3261.html#section-13.2.2.4).
  For 2xx responses, ACK is a separate transaction. For non-2xx, it's part of the
  INVITE transaction.

  Usually returns `{:noreply, state}` as ACK doesn't need a response.

  ## Parameters

  - `request` - The ACK request message
  - `state` - Current handler state

  ## Returns

  Standard handler response tuple (usually `{:noreply, state}`).

  ## Example

      @impl true
      def handle_ack(message, state) do
        # ACK received, call is now fully established
        Logger.info("Call established: \#{message.headers["call-id"]}")
        
        {:noreply, state}
      end
  """
  @callback handle_ack(request, state) :: response

  @doc """
  Handle arbitrary Erlang messages sent to the handler process.

  This callback is called when the handler receives non-SIP messages via
  `send/2` or similar. Useful for:
  - Timers
  - Internal events
  - Integration with other parts of your system

  ## Parameters

  - `msg` - Any Erlang term
  - `state` - Current handler state

  ## Returns

  - `{:noreply, state}` - Continue with new state
  - `{:stop, reason, state}` - Stop the handler

  ## Example

      @impl true
      def handle_info({:call_timeout, call_id}, state) do
        # Hangup calls that have been active too long
        case Map.get(state.calls, call_id) do
          nil -> 
            {:noreply, state}
          _call ->
            send_bye(call_id)
            {:noreply, remove_call(state, call_id)}
        end
      end
  """
  @callback handle_info(msg :: term(), state) ::
              {:noreply, state} | {:stop, reason :: term(), state}

  # Transaction-level handlers for advanced use cases

  @callback handle_transaction_invite_trying(request, transaction, state) :: response

  @doc false
  @callback handle_transaction_invite_proceeding(request, transaction, state) :: response

  @doc false
  @callback handle_transaction_invite_completed(request, transaction, state) :: response

  # Dialog-level handlers for advanced use cases

  @doc false
  @callback handle_dialog_early(request, dialog, state) :: response

  @doc false
  @callback handle_dialog_confirmed(request, dialog, state) :: response

  # All callbacks are optional except init
  @optional_callbacks [
    handle_invite: 2,
    handle_options: 2,
    handle_register: 2,
    handle_subscribe: 2,
    handle_notify: 2,
    handle_publish: 2,
    handle_message: 2,
    handle_bye: 2,
    handle_cancel: 2,
    handle_info: 2,
    handle_ack: 2,
    handle_transaction_invite_trying: 3,
    handle_transaction_invite_proceeding: 3,
    handle_transaction_invite_completed: 3,
    handle_dialog_early: 3,
    handle_dialog_confirmed: 3
  ]

  @doc """
  Use this module to implement the UAS Handler behaviour with default implementations.

  When you `use Parrot.UasHandler`, you get:

  - The `@behaviour Parrot.UasHandler` declaration
  - Default implementations for all callbacks
  - The ability to override only the callbacks you need

  ## Example

      defmodule MyApp.UasHandler do
        use Parrot.UasHandler
        
        @impl true
        def init(args) do
          {:ok, %{}}
        end
        
        @impl true
        def handle_invite(message, state) do
          # Your custom INVITE handling
          {:respond, 200, "OK", %{}, "", state}
        end
        
        # All other methods will use the default implementations
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Parrot.UasHandler

      # Default implementations
      @impl true
      def init(args) do
        {:ok, args}
      end

      @impl true
      def handle_invite(_request, state) do
        {:respond, 501, "Not Implemented", %{}, "", state}
      end

      @impl true
      def handle_options(_request, state) do
        headers = %{
          "allow" => "INVITE, ACK, CANCEL, BYE, OPTIONS",
          "accept" => "application/sdp"
        }

        {:respond, 200, "OK", headers, "", state}
      end

      @impl true
      def handle_register(_request, state) do
        {:respond, 501, "Not Implemented", %{}, "", state}
      end

      @impl true
      def handle_subscribe(_request, state) do
        {:respond, 501, "Not Implemented", %{}, "", state}
      end

      @impl true
      def handle_notify(_request, state) do
        {:respond, 501, "Not Implemented", %{}, "", state}
      end

      @impl true
      def handle_publish(_request, state) do
        {:respond, 501, "Not Implemented", %{}, "", state}
      end

      @impl true
      def handle_message(_request, state) do
        {:respond, 501, "Not Implemented", %{}, "", state}
      end

      @impl true
      def handle_bye(_request, state) do
        {:respond, 200, "OK", %{}, "", state}
      end

      @impl true
      def handle_cancel(_request, state) do
        {:respond, 200, "OK", %{}, "", state}
      end

      @impl true
      def handle_info(_request, state) when is_map(_request) do
        # This is for SIP INFO requests
        {:respond, 501, "Not Implemented", %{}, "", state}
      end

      @impl true
      def handle_ack(_request, state) do
        {:noreply, state}
      end

      @impl true
      def handle_info(_msg, state) do
        # This is for Erlang messages
        {:noreply, state}
      end

      # Allow overriding
      defoverridable init: 1,
                     handle_invite: 2,
                     handle_options: 2,
                     handle_register: 2,
                     handle_subscribe: 2,
                     handle_notify: 2,
                     handle_publish: 2,
                     handle_message: 2,
                     handle_bye: 2,
                     handle_cancel: 2,
                     handle_info: 2,
                     handle_ack: 2
    end
  end
end

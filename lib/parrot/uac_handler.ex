defmodule Parrot.UacHandler do
  @moduledoc """
  Behaviour for implementing SIP UAC (User Agent Client) handlers in Parrot.

  The `Parrot.UacHandler` behaviour is the primary interface for building SIP client applications
  with the Parrot framework. By implementing this behaviour, you can send SIP requests
  and handle responses in a structured way.

  This behaviour follows the SIP protocol as defined in [RFC 3261](https://www.rfc-editor.org/rfc/rfc3261.html).

  ## Summary

  Parrot handles all the complex SIP protocol details (transactions, retransmissions,
  timers, dialog state) automatically. Your handler only needs to implement the business
  logic for handling responses to requests you send.

  ## Basic Usage

  ```elixir
  defmodule MyApp.UacHandler do
    use Parrot.UacHandler

    @impl true
    def init(args) do
      {:ok, %{calls: %{}}}
    end

    @impl true
    def handle_provisional(%{status_code: 180} = response, state) do
      IO.puts("Phone is ringing...")
      {:ok, state}
    end

    @impl true
    def handle_success(%{status_code: 200} = response, state) do
      IO.puts("Call answered!")
      # Process SDP answer, send ACK
      {:ok, state}
    end

    @impl true
    def handle_client_error(%{status_code: 404} = response, state) do
      IO.puts("User not found")
      {:ok, state}
    end
  end
  ```

  ## State Management

  Each handler instance maintains its own state across the lifecycle of a transaction/dialog.
  The state is passed to each callback and the updated state from your response is
  preserved for subsequent callbacks.

  ## Response Handling

  UAC handlers process different categories of SIP responses:
  - 1xx (Provisional) - Request is being processed
  - 2xx (Success) - Request was successful
  - 3xx (Redirection) - Request should be redirected
  - 4xx (Client Error) - Request contains bad syntax or cannot be fulfilled
  - 5xx (Server Error) - Server failed to fulfill a valid request
  - 6xx (Global Failure) - Request cannot be fulfilled at any server

  ## Callback Return Values

  Handler callbacks can return:
  - `{:ok, state}` - Continue with updated state
  - `{:stop, reason, state}` - Stop the handler process
  - `{:send_ack, ack_headers, ack_body, state}` - Send ACK for 2xx to INVITE (automatic if not specified)
  - `{:follow_redirect, state}` - Follow 3xx redirect (if Contact header present)

  ## Using the Behaviour

  When you `use Parrot.UacHandler`, default implementations are provided for all callbacks
  that simply log the response and continue. You only need to override the callbacks
  for response types your application needs to handle specially.
  """

  require Logger

  @typedoc """
  A SIP response message.

  This is a `Parrot.Sip.Message` struct with at least these fields:
  - `type` - Always `:response`
  - `status` - Status code (100-699)
  - `reason` - Reason phrase
  - `headers` - Map of headers with lowercase string keys
  - `body` - Binary message body
  """
  @type response :: Parrot.Sip.Message.t()

  @typedoc """
  Possible return values from handler callbacks.

  - `{:ok, state}` - Continue processing with new state
  - `{:stop, reason, state}` - Stop the handler process
  - `{:send_ack, headers, body, state}` - Send ACK with specific headers/body (INVITE 2xx only)
  - `{:follow_redirect, state}` - Automatically follow 3xx redirect
  """
  @type callback_result ::
          {:ok, state}
          | {:stop, reason :: term(), state}
          | {:send_ack, headers :: map(), body :: binary(), state}
          | {:follow_redirect, state}

  @typedoc "Handler state - can be any term"
  @type state :: term()

  @typedoc "Callback function passed to low-level UAC"
  @type callback :: (Parrot.Sip.UAC.client_trans_result() -> any())

  # Core callbacks

  @doc """
  Initialize the handler state.

  Called when a new UAC handler process is started.

  ## Parameters

  - `args` - Arguments passed when starting the handler

  ## Returns

  - `{:ok, state}` - Initialize with the given state
  - `{:stop, reason}` - Prevent the handler from starting

  ## Example

      @impl true
      def init(_args) do
        {:ok, %{
          active_calls: %{},
          config: Application.get_env(:my_app, :sip_config)
        }}
      end
  """
  @callback init(args :: term()) :: {:ok, state} | {:stop, reason :: term()}

  # Response handlers by status code range

  @doc """
  Handle provisional responses (100-199).

  These responses indicate that the request has been received and is being processed.
  Common provisional responses:
  - 100 Trying - Request received, processing
  - 180 Ringing - Called party is being alerted
  - 181 Call Is Being Forwarded
  - 182 Queued
  - 183 Session Progress

  ## Parameters

  - `response` - The provisional response message
  - `state` - Current handler state

  ## Returns

  Standard handler callback result.

  ## Example

      @impl true
      def handle_provisional(%{status_code: 180} = response, state) do
        Logger.info("Call is ringing to \#{inspect(response.headers["to"])}")
        {:ok, state}
      end
  """
  @callback handle_provisional(response, state) :: callback_result

  @doc """
  Handle success responses (200-299).

  These responses indicate the request was successfully received, understood, and accepted.
  Common success responses:
  - 200 OK - Request succeeded
  - 202 Accepted - Request accepted for processing

  For 200 OK to INVITE, you typically need to:
  1. Process the SDP answer
  2. Send an ACK
  3. Establish media

  ## Parameters

  - `response` - The success response message
  - `state` - Current handler state

  ## Returns

  Standard handler callback result. For INVITE 200 OK, can also return
  `{:send_ack, headers, body, state}` to customize the ACK.

  ## Example

      @impl true
      def handle_success(%{status_code: 200, headers: %{"cseq" => %{method: "INVITE"}}} = response, state) do
        # Process SDP answer
        sdp_answer = response.body
        media_state = process_sdp_answer(sdp_answer)
        
        # ACK will be sent automatically unless we return {:send_ack, ...}
        {:ok, put_in(state, [:calls, response.call_id, :media], media_state)}
      end
  """
  @callback handle_success(response, state) :: callback_result

  @doc """
  Handle redirection responses (300-399).

  These responses indicate the request must be redirected to different location(s).
  Common redirection responses:
  - 300 Multiple Choices
  - 301 Moved Permanently
  - 302 Moved Temporarily
  - 305 Use Proxy
  - 380 Alternative Service

  ## Parameters

  - `response` - The redirection response message
  - `state` - Current handler state

  ## Returns

  Standard handler callback result. Can return `{:follow_redirect, state}` to
  automatically follow the redirect using Contact headers.

  ## Example

      @impl true
      def handle_redirect(%{status_code: 302} = response, state) do
        case response.headers["contact"] do
          nil -> 
            {:stop, :no_redirect_contact, state}
          _contact ->
            # Automatically follow the redirect
            {:follow_redirect, state}
        end
      end
  """
  @callback handle_redirect(response, state) :: callback_result

  @doc """
  Handle client error responses (400-499).

  These responses indicate the request contains bad syntax or cannot be fulfilled.
  Common client errors:
  - 400 Bad Request
  - 401 Unauthorized
  - 403 Forbidden
  - 404 Not Found
  - 405 Method Not Allowed
  - 407 Proxy Authentication Required
  - 408 Request Timeout
  - 486 Busy Here
  - 487 Request Terminated

  ## Parameters

  - `response` - The client error response message
  - `state` - Current handler state

  ## Returns

  Standard handler callback result.

  ## Example

      @impl true
      def handle_client_error(%{status_code: 401} = response, state) do
        case authenticate(response, state) do
          {:ok, auth_headers} ->
            # Retry with authentication
            resend_with_auth(auth_headers, state)
          :error ->
            {:stop, :authentication_failed, state}
        end
      end
  """
  @callback handle_client_error(response, state) :: callback_result

  @doc """
  Handle server error responses (500-599).

  These responses indicate the server failed to fulfill an apparently valid request.
  Common server errors:
  - 500 Server Internal Error
  - 501 Not Implemented
  - 502 Bad Gateway
  - 503 Service Unavailable
  - 504 Server Time-out
  - 505 Version Not Supported

  ## Parameters

  - `response` - The server error response message
  - `state` - Current handler state

  ## Returns

  Standard handler callback result.

  ## Example

      @impl true
      def handle_server_error(%{status_code: 503} = response, state) do
        Logger.error("Service unavailable: \#{response.reason_phrase}")
        # Maybe retry later
        schedule_retry(state)
        {:ok, state}
      end
  """
  @callback handle_server_error(response, state) :: callback_result

  @doc """
  Handle global failure responses (600-699).

  These responses indicate the request cannot be fulfilled at any server.
  Common global failures:
  - 600 Busy Everywhere
  - 603 Decline
  - 604 Does Not Exist Anywhere
  - 606 Not Acceptable

  ## Parameters

  - `response` - The global failure response message
  - `state` - Current handler state

  ## Returns

  Standard handler callback result.
  """
  @callback handle_global_failure(response, state) :: callback_result

  @doc """
  Handle errors from the transaction layer.

  Called when the transaction encounters an error (timeout, transport failure, etc).

  ## Parameters

  - `error` - Error term from the transaction layer
  - `state` - Current handler state

  ## Returns

  Standard handler callback result.

  ## Example

      @impl true
      def handle_error(:timeout, state) do
        Logger.error("Request timed out")
        cleanup_resources(state)
        {:stop, :timeout, state}
      end
  """
  @callback handle_error(error :: term(), state) :: callback_result

  @doc """
  Handle a call being fully established.

  Called after successful INVITE/200/ACK exchange when the dialog is confirmed.
  This is where you typically start media streams.

  ## Parameters

  - `dialog_id` - Identifier for the established dialog
  - `state` - Current handler state

  ## Returns

  - `{:ok, state}` - Continue with updated state
  - `{:stop, reason, state}` - Stop the handler

  ## Example

      @impl true
      def handle_call_established(dialog_id, state) do
        Logger.info("Call established: \#{inspect(dialog_id)}")
        start_media_streams(dialog_id, state)
        {:ok, state}
      end
  """
  @callback handle_call_established(dialog_id :: term(), state) ::
              {:ok, state} | {:stop, reason :: term(), state}

  @doc """
  Handle a call ending.

  Called when the dialog is terminated (BYE received/sent, or error).

  ## Parameters

  - `dialog_id` - Identifier for the ended dialog
  - `reason` - Reason for call ending
  - `state` - Current handler state

  ## Returns

  - `{:ok, state}` - Continue with updated state
  - `{:stop, reason, state}` - Stop the handler

  ## Example

      @impl true
      def handle_call_ended(dialog_id, reason, state) do
        Logger.info("Call ended: \#{inspect(dialog_id)}, reason: \#{inspect(reason)}")
        cleanup_call_resources(dialog_id, state)
        {:ok, remove_call(state, dialog_id)}
      end
  """
  @callback handle_call_ended(dialog_id :: term(), reason :: term(), state) ::
              {:ok, state} | {:stop, reason :: term(), state}

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
      def handle_info({:media_timeout, call_id}, state) do
        # End calls that have no media activity
        send_bye(call_id)
        {:noreply, state}
      end
  """
  @callback handle_info(msg :: term(), state) ::
              {:noreply, state} | {:stop, reason :: term(), state}

  # All callbacks are optional except init
  @optional_callbacks [
    handle_provisional: 2,
    handle_success: 2,
    handle_redirect: 2,
    handle_client_error: 2,
    handle_server_error: 2,
    handle_global_failure: 2,
    handle_error: 2,
    handle_call_established: 2,
    handle_call_ended: 3,
    handle_info: 2
  ]

  @doc """
  Use this module to implement the UacHandler behaviour with default implementations.

  When you `use Parrot.UacHandler`, you get:

  - The `@behaviour Parrot.UacHandler` declaration
  - Default implementations for all callbacks
  - The ability to override only the callbacks you need

  ## Example

      defmodule MyApp.UacHandler do
        use Parrot.UacHandler
        
        @impl true
        def init(args) do
          {:ok, %{}}
        end
        
        @impl true
        def handle_success(response, state) do
          # Your custom success handling
          Logger.info("Got success: \#{response.status_code}")
          {:ok, state}
        end
        
        # All other responses will use the default implementations
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Parrot.UacHandler
      require Logger

      # Default implementations
      @impl true
      def init(args) do
        {:ok, args}
      end

      @impl true
      def handle_provisional(response, state) do
        Logger.debug(
          "UAC received provisional response: \#{response.status_code} \#{response.reason_phrase}"
        )

        {:ok, state}
      end

      @impl true
      def handle_success(response, state) do
        Logger.info(
          "UAC received success response: \#{response.status_code} \#{response.reason_phrase}"
        )

        {:ok, state}
      end

      @impl true
      def handle_redirect(response, state) do
        Logger.info(
          "UAC received redirect response: \#{response.status_code} \#{response.reason_phrase}"
        )

        # By default, don't follow redirects automatically
        {:ok, state}
      end

      @impl true
      def handle_client_error(response, state) do
        Logger.warning(
          "UAC received client error: \#{response.status_code} \#{response.reason_phrase}"
        )

        {:ok, state}
      end

      @impl true
      def handle_server_error(response, state) do
        Logger.error(
          "UAC received server error: \#{response.status_code} \#{response.reason_phrase}"
        )

        {:ok, state}
      end

      @impl true
      def handle_global_failure(response, state) do
        Logger.error(
          "UAC received global failure: \#{response.status_code} \#{response.reason_phrase}"
        )

        {:ok, state}
      end

      @impl true
      def handle_error(error, state) do
        Logger.error("UAC transaction error: \#{inspect(error)}")
        {:stop, error, state}
      end

      @impl true
      def handle_call_established(dialog_id, state) do
        Logger.info("UAC call established: \#{inspect(dialog_id)}")
        {:ok, state}
      end

      @impl true
      def handle_call_ended(dialog_id, reason, state) do
        Logger.info("UAC call ended: \#{inspect(dialog_id)}, reason: \#{inspect(reason)}")
        {:ok, state}
      end

      @impl true
      def handle_info(_msg, state) do
        {:noreply, state}
      end

      # Allow overriding
      defoverridable init: 1,
                     handle_provisional: 2,
                     handle_success: 2,
                     handle_redirect: 2,
                     handle_client_error: 2,
                     handle_server_error: 2,
                     handle_global_failure: 2,
                     handle_error: 2,
                     handle_call_established: 2,
                     handle_call_ended: 3,
                     handle_info: 2
    end
  end
end

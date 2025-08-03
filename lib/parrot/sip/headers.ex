defmodule Parrot.Sip.Headers do
  @moduledoc """
  A module providing a unified interface to all SIP header modules.

  This module serves as an entry point for working with SIP headers,
  delegating to specialized header modules like Via, From, To, etc.
  """

  alias Parrot.Sip.{
    Method,
    Branch,
    DialogId,
    MethodSet
  }

  alias Parrot.Sip.Headers.{
    Via,
    From,
    To,
    Contact,
    CSeq,
    CallId,
    ContentType,
    ContentLength,
    MaxForwards,
    Route,
    RecordRoute,
    Supported,
    Allow,
    Expires,
    ReferTo,
    Subject,
    Event,
    SubscriptionState,
    Accept
  }

  @doc """
  Parses a Via header value.
  """
  defdelegate parse_via(value), to: Via, as: :parse

  @doc """
  Creates a new Via header.
  """
  defdelegate new_via(host, transport \\ "udp", port \\ nil, parameters \\ %{}), to: Via, as: :new

  @doc """
  Creates a new Via header with a randomly generated branch parameter.
  """
  defdelegate new_via_with_branch(host, transport \\ "udp", port \\ nil, parameters \\ %{}),
    to: Via,
    as: :new_with_branch

  @doc """
  Formats a Via header as a string.
  """
  defdelegate format_via(via), to: Via, as: :format

  @doc """
  Generates a unique branch parameter for a Via header.
  """
  defdelegate generate_branch(), to: Via

  @doc """
  Parses a From header value.
  """
  defdelegate parse_from(value), to: From, as: :parse

  @doc """
  Creates a new From header.
  """
  defdelegate new_from(uri, display_name \\ nil, parameters \\ %{}), to: From, as: :new

  @doc """
  Creates a new From header with a randomly generated tag parameter.
  """
  defdelegate new_from_with_tag(uri, display_name \\ nil, parameters \\ %{}),
    to: From,
    as: :new_with_tag

  @doc """
  Generates a unique tag parameter.
  """
  defdelegate generate_tag(), to: From

  @doc """
  Generates a branch parameter for a message with specific properties.

  See `Parrot.Sip.Branch.generate_for_message/5`.
  """
  defdelegate generate_branch_for_message(method, request_uri, from_tag, to_tag, call_id),
    to: Branch,
    as: :generate_for_message

  @doc """
  Checks if a branch parameter is RFC 3261 compliant.

  See `Parrot.Sip.Branch.is_rfc3261_compliant?/1`.
  """
  defdelegate is_rfc3261_compliant_branch?(branch), to: Branch, as: :is_rfc3261_compliant?

  @doc """
  Ensures a branch parameter is RFC 3261 compliant.

  See `Parrot.Sip.Branch.ensure_rfc3261_compliance/1`.
  """
  defdelegate ensure_rfc3261_branch_compliance(branch), to: Branch, as: :ensure_rfc3261_compliance

  @doc """
  Parses a To header value.
  """
  defdelegate parse_to(value), to: To, as: :parse

  @doc """
  Creates a new To header.
  """
  defdelegate new_to(uri, display_name \\ nil, parameters \\ %{}), to: To, as: :new

  @doc """
  Creates a new To header with a tag parameter.
  """
  defdelegate new_to_with_tag(uri, display_name \\ nil, tag), to: To, as: :new_with_tag

  @doc """
  Formats a To header as a string.
  """
  defdelegate format_to(to), to: To, as: :format

  @doc """
  Parses a Contact header value.
  """
  defdelegate parse_contact(value), to: Contact, as: :parse

  @doc """
  Creates a new Contact header.
  """
  defdelegate new_contact(uri, display_name \\ nil, parameters \\ %{}), to: Contact, as: :new

  @doc """
  Creates a wildcard Contact header (*).
  """
  defdelegate wildcard_contact(), to: Contact, as: :wildcard

  @doc """
  Formats a Contact header as a string.
  """
  defdelegate format_contact(contact), to: Contact, as: :format

  @doc """
  Parses a method from a string.

  See `Parrot.Sip.Method.parse/1`.
  """
  defdelegate parse_method(method_str), to: Method, as: :parse

  @doc """
  Parses a method from a string, raising on error.

  See `Parrot.Sip.Method.parse!/1`.
  """
  defdelegate parse_method!(method_str), to: Method, as: :parse!

  @doc """
  Converts a method to its string representation.

  See `Parrot.Sip.Method.to_string/1`.
  """
  defdelegate method_to_string(method), to: Method, as: :to_string

  @doc """
  Returns all standard SIP methods.

  See `Parrot.Sip.Method.standard_methods/0`.
  """
  defdelegate standard_methods(), to: Method, as: :standard_methods

  @doc """
  Checks if a method is a standard SIP method.

  See `Parrot.Sip.Method.is_standard?/1`.
  """
  defdelegate is_standard_method?(method), to: Method, as: :is_standard?

  @doc """
  Parses a CSeq header value.
  """
  defdelegate parse_cseq(value), to: CSeq, as: :parse

  @doc """
  Creates a new CSeq header.
  """
  defdelegate new_cseq(number, method), to: CSeq, as: :new

  @doc """
  Formats a CSeq header as a string.
  """
  defdelegate format_cseq(cseq), to: CSeq, as: :format

  @doc """
  Parses a Call-ID header value.
  """
  defdelegate parse_call_id(value), to: CallId, as: :parse

  @doc """
  Formats a Call-ID header value.
  """
  defdelegate format_call_id(call_id), to: CallId, as: :format

  @doc """
  Generates a unique Call-ID with a specified host.
  """
  defdelegate generate_call_id(host), to: CallId, as: :generate

  @doc """
  Generates a unique Call-ID with a default host.
  """
  defdelegate generate_call_id(), to: CallId, as: :generate

  @doc """
  Parses a Content-Type header value.
  """
  defdelegate parse_content_type(value), to: ContentType, as: :parse

  @doc """
  Formats a Content-Type header value.
  """
  defdelegate format_content_type(content_type), to: ContentType, as: :format

  @doc """
  Creates a Content-Type header value with parameters.
  """
  defdelegate create_content_type(media_type, parameters \\ %{}), to: ContentType, as: :create

  @doc """
  Extracts the media type from a Content-Type header value.
  """
  defdelegate content_type_media_type(content_type), to: ContentType, as: :media_type

  @doc """
  Extracts parameters from a Content-Type header value.
  """
  defdelegate content_type_parameters(content_type), to: ContentType, as: :parameters

  @doc """
  Parses a Content-Length header value.
  """
  defdelegate parse_content_length(value), to: ContentLength, as: :parse

  @doc """
  Formats a Content-Length header value.
  """
  defdelegate format_content_length(content_length), to: ContentLength, as: :format

  @doc """
  Calculates the Content-Length for a given body.
  """
  defdelegate calculate_content_length(body), to: ContentLength, as: :calculate

  @doc """
  Creates a Content-Length header value for a given body.
  """
  defdelegate create_content_length(body), to: ContentLength, as: :create

  @doc """
  Parses a Max-Forwards header value.
  """
  defdelegate parse_max_forwards(value), to: MaxForwards, as: :parse

  @doc """
  Creates a new Max-Forwards header with the specified value.
  """
  defdelegate new_max_forwards(value), to: MaxForwards, as: :new

  @doc """
  Creates a new Max-Forwards header with the default value of 70.
  """
  defdelegate default_max_forwards(), to: MaxForwards, as: :default

  @doc """
  Formats a Max-Forwards header value.
  """
  defdelegate format_max_forwards(value), to: MaxForwards, as: :format

  @doc """
  Decrements a Max-Forwards header value.
  """
  defdelegate decrement_max_forwards(value), to: MaxForwards, as: :decrement

  @doc """
  Checks if a Max-Forwards header value has reached zero.
  """
  defdelegate max_forwards_zero?(value), to: MaxForwards, as: :zero?

  @doc """
  Parses a Route header value.
  """
  defdelegate parse_route(value), to: Route, as: :parse

  @doc """
  Creates a new Route header.
  """
  defdelegate new_route(uri, display_name \\ nil, parameters \\ %{}), to: Route, as: :new

  @doc """
  Formats a Route header as a string.
  """
  defdelegate format_route(route), to: Route, as: :format

  @doc """
  Parses a list of Route headers.
  """
  defdelegate parse_route_list(value), to: Route, as: :parse_list

  @doc """
  Formats a list of Route headers as a string.
  """
  defdelegate format_route_list(routes), to: Route, as: :format_list

  @doc """
  Parses a Record-Route header value.
  """
  defdelegate parse_record_route(value), to: RecordRoute, as: :parse

  @doc """
  Creates a new Record-Route header.
  """
  defdelegate new_record_route(uri, display_name \\ nil, parameters \\ %{}),
    to: RecordRoute,
    as: :new

  @doc """
  Formats a Record-Route header as a string.
  """
  defdelegate format_record_route(record_route), to: RecordRoute, as: :format

  @doc """
  Parses a list of Record-Route headers.
  """
  defdelegate parse_record_route_list(value), to: RecordRoute, as: :parse_list

  @doc """
  Formats a list of Record-Route headers as a string.
  """
  defdelegate format_record_route_list(record_routes), to: RecordRoute, as: :format_list

  @doc """
  Parses a Supported header value.
  """
  defdelegate parse_supported(value), to: Supported, as: :parse

  @doc """
  Creates a new Supported header.
  """
  defdelegate new_supported(options), to: Supported, as: :new

  @doc """
  Formats a Supported header as a string.
  """
  defdelegate format_supported(options), to: Supported, as: :format

  @doc """
  Adds an option to the Supported header.
  """
  defdelegate add_supported_option(options, option), to: Supported, as: :add

  @doc """
  Removes an option from the Supported header.
  """
  defdelegate remove_supported_option(options, option), to: Supported, as: :remove

  @doc """
  Checks if a specific option is supported.
  """
  defdelegate supports?(options, option), to: Supported, as: :supports?

  @doc """
  Parses an Allow header value.
  """
  defdelegate parse_allow(value), to: Allow, as: :parse

  @doc """
  Creates a new Allow header.
  """
  defdelegate new_allow(methods), to: Allow, as: :new

  @doc """
  Creates a standard set of common SIP methods.
  """
  defdelegate standard_allow(), to: Allow, as: :standard

  @doc """
  Formats an Allow header as a string.
  """
  defdelegate format_allow(methods), to: Allow, as: :format

  @doc """
  Adds a method to the Allow header.
  """
  defdelegate add_allow_method(methods, method), to: Allow, as: :add

  @doc """
  Removes a method from the Allow header.
  """
  defdelegate remove_allow_method(methods, method), to: Allow, as: :remove

  @doc """
  Checks if a specific method is allowed.
  """
  defdelegate allows?(methods, method), to: Allow, as: :allows?

  @doc """
  Parses an Expires header value.
  """
  defdelegate parse_expires(value), to: Expires, as: :parse

  @doc """
  Creates a new Expires header.
  """
  defdelegate new_expires(seconds), to: Expires, as: :new

  @doc """
  Creates a default Expires header with a value of 3600 seconds (1 hour).
  """
  defdelegate default_expires(), to: Expires, as: :default

  @doc """
  Formats an Expires header as a string.
  """
  defdelegate format_expires(value), to: Expires, as: :format

  @doc """
  Checks if an Expires value has expired based on a reference time.
  """
  defdelegate expires_expired?(expires_time, reference_time \\ DateTime.utc_now()),
    to: Expires,
    as: :expired?

  @doc """
  Calculates an expiration DateTime from a duration in seconds.
  """
  defdelegate calculate_expiry(seconds, reference_time \\ DateTime.utc_now()),
    to: Expires,
    as: :calculate_expiry

  @doc """
  Calculates the remaining time in seconds until expiration.
  """
  defdelegate remaining_seconds(expires_time, reference_time \\ DateTime.utc_now()),
    to: Expires,
    as: :remaining_seconds

  @doc """
  Parses a Refer-To header value.
  """
  defdelegate parse_refer_to(value), to: ReferTo, as: :parse

  @doc """
  Creates a new Refer-To header.
  """
  defdelegate new_refer_to(uri, display_name \\ nil, parameters \\ %{}), to: ReferTo, as: :new

  @doc """
  Formats a Refer-To header as a string.
  """
  defdelegate format_refer_to(refer_to), to: ReferTo, as: :format

  @doc """
  Extracts URI parameters from a Refer-To header.
  """
  defdelegate refer_to_uri_parameters(refer_to), to: ReferTo, as: :uri_parameters

  @doc """
  Extracts URI headers from a Refer-To header.
  """
  defdelegate refer_to_uri_headers(refer_to), to: ReferTo, as: :uri_headers

  @doc """
  Gets the Replaces parameter from the Refer-To header.
  """
  defdelegate refer_to_replaces(refer_to), to: ReferTo, as: :replaces

  @doc """
  Parses the Replaces parameter into its components.
  """
  defdelegate parse_refer_to_replaces(refer_to), to: ReferTo, as: :parse_replaces

  @doc """
  Parses a Subject header value.
  """
  defdelegate parse_subject(value), to: Subject, as: :parse

  @doc """
  Creates a new Subject header.
  """
  defdelegate new_subject(value), to: Subject, as: :new

  @doc """
  Formats a Subject header as a string.
  """
  defdelegate format_subject(subject), to: Subject, as: :format

  @doc """
  Parses an Event header value.
  """
  defdelegate parse_event(value), to: Event, as: :parse

  @doc """
  Creates a new Event header.
  """
  defdelegate new_event(event, parameters \\ %{}), to: Event, as: :new

  @doc """
  Formats an Event header as a string.
  """
  defdelegate format_event(event), to: Event, as: :format

  @doc """
  Gets a parameter from an Event header.
  """
  defdelegate get_event_parameter(event, key), to: Event, as: :get_parameter

  @doc """
  Sets a parameter in an Event header.
  """
  defdelegate set_event_parameter(event, key, value), to: Event, as: :set_parameter

  @doc """
  Parses a Subscription-State header value.
  """
  defdelegate parse_subscription_state(value), to: SubscriptionState, as: :parse

  @doc """
  Creates a new Subscription-State header.
  """
  defdelegate new_subscription_state(state, parameters \\ %{}), to: SubscriptionState, as: :new

  @doc """
  Formats a Subscription-State header as a string.
  """
  defdelegate format_subscription_state(subscription_state), to: SubscriptionState, as: :format

  @doc """
  Sets the reason parameter in a Subscription-State header.
  """
  defdelegate set_subscription_state_reason(reason, subscription_state),
    to: SubscriptionState,
    as: :set_reason

  @doc """
  Sets the expires parameter in a Subscription-State header.
  """
  defdelegate set_subscription_state_expires(expires, subscription_state),
    to: SubscriptionState,
    as: :set_expires

  @doc """
  Checks if a Subscription-State is terminated.
  """
  defdelegate subscription_state_terminated?(subscription_state),
    to: SubscriptionState,
    as: :terminated?

  @doc """
  Parses an Accept header value.
  """
  defdelegate parse_accept(value), to: Accept, as: :parse

  @doc """
  Creates a new Accept header.
  """
  defdelegate new_accept(type, subtype, parameters \\ %{}, q_value \\ nil), to: Accept, as: :new

  @doc """
  Formats an Accept header as a string.
  """
  defdelegate format_accept(accept), to: Accept, as: :format

  @doc """
  Creates a new Accept header for application/sdp.
  """
  defdelegate sdp_accept(), to: Accept, as: :sdp

  @doc """
  Creates a new Accept header for all media types (*/*).
  """
  defdelegate all_accept(), to: Accept, as: :all

  @doc """
  Creates a dialog ID from a SIP message.

  See `Parrot.Sip.DialogId.from_message/1`.
  """
  defdelegate dialog_id_from_message(message), to: DialogId, as: :from_message

  @doc """
  Creates a dialog ID with explicit components.

  See `Parrot.Sip.DialogId.new/4`.
  """
  defdelegate new_dialog_id(call_id, local_tag, remote_tag \\ nil, direction \\ :uac),
    to: DialogId,
    as: :new

  @doc """
  Checks if a dialog ID is complete.

  See `Parrot.Sip.DialogId.is_complete?/1`.
  """
  defdelegate is_dialog_complete?(dialog_id), to: DialogId, as: :is_complete?

  @doc """
  Creates a peer dialog ID by swapping local and remote tags.

  See `Parrot.Sip.DialogId.peer_dialog_id/1`.
  """
  defdelegate peer_dialog_id(dialog_id), to: DialogId, as: :peer_dialog_id

  @doc """
  Compares two dialog IDs to determine if they match.

  See `Parrot.Sip.DialogId.match?/2`.
  """
  defdelegate dialog_ids_match?(dialog_id1, dialog_id2), to: DialogId, as: :match?

  @doc """
  Creates a new method set.

  See `Parrot.Sip.MethodSet.new/0` and `Parrot.Sip.MethodSet.new/1`.
  """
  defdelegate new_method_set(methods \\ []), to: MethodSet, as: :new

  @doc """
  Creates a method set containing all standard SIP methods.

  See `Parrot.Sip.MethodSet.standard_methods/0`.
  """
  defdelegate standard_method_set(), to: MethodSet, as: :standard_methods

  @doc """
  Creates a method set containing the basic dialog methods.

  See `Parrot.Sip.MethodSet.dialog_methods/0`.
  """
  defdelegate dialog_method_set(), to: MethodSet, as: :dialog_methods

  @doc """
  Formats a method set as a string for the Allow header.

  See `Parrot.Sip.MethodSet.to_allow_string/1`.
  """
  defdelegate method_set_to_allow_string(method_set), to: MethodSet, as: :to_allow_string

  @doc """
  Creates a method set from an Allow header string.

  See `Parrot.Sip.MethodSet.from_allow_string/1`.
  """
  defdelegate method_set_from_allow_string(allow_string), to: MethodSet, as: :from_allow_string
end

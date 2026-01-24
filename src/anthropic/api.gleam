//// API functions for Anthropic Messages API
////
//// This module provides the core functions for interacting with Claude's
//// Messages API, including message creation and response parsing.
////
//// ## Quick Start
////
//// For most use cases, use the unified chat functions:
////
//// ```gleam
//// import anthropic/api
//// import anthropic/client
//// import anthropic/types/request
//// import anthropic/types/message.{user_message}
////
//// // Initialize client
//// let assert Ok(client) = client.init()
////
//// // Create a request
//// let req = request.new(
////   "claude-sonnet-4-20250514",
////   [user_message("Hello, Claude!")],
////   1024,
//// )
////
//// // Non-streaming chat
//// case api.chat(client, req) {
////   Ok(response) -> io.println(request.response_text(response))
////   Error(err) -> io.println(error.error_to_string(err))
//// }
////
//// // Streaming chat (batch mode - collects all events)
//// case api.chat_stream(client, req) {
////   Ok(result) -> io.println(api.stream_text(result))
////   Error(err) -> io.println(error.error_to_string(err))
//// }
//// ```

import anthropic/client.{type Client, messages_endpoint}
import anthropic/config.{api_key_to_string}
import anthropic/error.{type AnthropicError}
import anthropic/internal/decoder
import anthropic/internal/sse
import anthropic/internal/validation
import anthropic/request.{type CreateMessageRequest, type CreateMessageResponse}
import anthropic/streaming.{type StreamEvent}
import anthropic/streaming/decoder as stream_decoder
import gleam/http as gleam_http
import gleam/http/request as http_request
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/list
import gleam/result
import gleam/string

// =============================================================================
// Message Creation
// =============================================================================

/// Create a message using the Anthropic Messages API
///
/// @deprecated Use `api.chat` instead for a more intuitive API
///
/// ## Example
///
/// ```gleam
/// // Prefer using api.chat instead:
/// case api.chat(client, request) {
///   Ok(response) -> io.println(response_text(response))
///   Error(err) -> io.println(error_to_string(err))
/// }
/// ```
@deprecated("Use api.chat instead")
pub fn create_message(
  client: Client,
  message_request: CreateMessageRequest,
) -> Result(CreateMessageResponse, AnthropicError) {
  chat(client, message_request)
}

// =============================================================================
// Response Parsing
// =============================================================================

/// Parse a response body into CreateMessageResponse
fn parse_response(body: String) -> Result(CreateMessageResponse, AnthropicError) {
  decoder.parse_response_body(body)
}

// =============================================================================
// Unified Chat API
// =============================================================================

/// Send a chat message and receive a response (non-streaming)
///
/// This is the primary function for interacting with Claude. It sends a message
/// and returns the complete response.
///
/// ## Example
///
/// ```gleam
/// import anthropic/api
/// import anthropic/client
/// import anthropic/types/request
/// import anthropic/types/message.{user_message}
///
/// let assert Ok(client) = client.init()
/// let req = request.new(
///   "claude-sonnet-4-20250514",
///   [user_message("What is the capital of France?")],
///   1024,
/// )
///
/// case api.chat(client, req) {
///   Ok(response) -> io.println(request.response_text(response))
///   Error(err) -> handle_error(err)
/// }
/// ```
pub fn chat(
  client: Client,
  message_request: CreateMessageRequest,
) -> Result(CreateMessageResponse, AnthropicError) {
  // Validate the request using shared validation module
  use _ <- result.try(validation.validate_request_or_error(message_request))

  // Encode request to JSON
  let body = request.request_to_json_string(message_request)

  // Make the API call
  use response_body <- result.try(client.post_and_handle(
    client,
    messages_endpoint,
    body,
  ))

  // Parse the response
  parse_response(response_body)
}

// =============================================================================
// Streaming Chat API
// =============================================================================

/// Result of a streaming chat request
pub type StreamResult {
  StreamResult(
    /// List of parsed streaming events
    events: List(StreamEvent),
  )
}

/// Error during streaming
pub type StreamError {
  /// HTTP-level error during request
  HttpError(error: AnthropicError)
  /// Error parsing SSE data
  SseParseError(message: String)
  /// Error decoding event JSON
  EventDecodeError(message: String)
  /// API returned an error response
  ApiError(status: Int, body: String)
}

/// Send a chat message with streaming response (batch mode)
///
/// This function sends a message and returns all streaming events after
/// the response completes. For true real-time streaming, use the sans-io
/// functions in `anthropic/streaming/handler`.
///
/// ## Example
///
/// ```gleam
/// import anthropic/api
/// import anthropic/client
/// import anthropic/types/request
/// import anthropic/types/message.{user_message}
///
/// let assert Ok(client) = client.init()
/// let req = request.new(
///   "claude-sonnet-4-20250514",
///   [user_message("Tell me a story")],
///   2048,
/// )
///
/// case api.chat_stream(client, req) {
///   Ok(result) -> io.println(api.stream_text(result))
///   Error(err) -> handle_stream_error(err)
/// }
/// ```
pub fn chat_stream(
  client: Client,
  message_request: CreateMessageRequest,
) -> Result(StreamResult, StreamError) {
  // Ensure streaming is enabled
  let streaming_request = request.with_stream(message_request, True)

  // Validate the request
  case validation.validate_request_or_error(streaming_request) {
    Error(err) -> Error(HttpError(error: err))
    Ok(_) -> {
      // Encode request to JSON
      let body = request.request_to_json_string(streaming_request)

      // Make the HTTP request
      case make_streaming_request(client, body) {
        Error(err) -> Error(HttpError(error: err))
        Ok(http_response) -> {
          case http_response.status {
            200 -> parse_sse_body(http_response.body)
            status -> Error(ApiError(status: status, body: http_response.body))
          }
        }
      }
    }
  }
}

/// Callback function type for processing streaming events
pub type EventCallback =
  fn(StreamEvent) -> Nil

/// Send a streaming chat message with a callback for each event
///
/// **Note**: Despite the callback, this function collects ALL events before
/// calling the callbacks. It does NOT provide true real-time streaming.
/// For real-time streaming, use the sans-io functions in `anthropic/streaming/handler`.
///
/// ## Example
///
/// ```gleam
/// api.chat_stream_with_callback(client, request, fn(event) {
///   case api.event_text(event) {
///     Ok(text) -> io.print(text)
///     Error(_) -> Nil
///   }
/// })
/// ```
pub fn chat_stream_with_callback(
  client: Client,
  message_request: CreateMessageRequest,
  callback: EventCallback,
) -> Result(StreamResult, StreamError) {
  use stream_result <- result.try(chat_stream(client, message_request))

  // Call callback for each event (after all collected)
  list.each(stream_result.events, callback)

  Ok(stream_result)
}

// =============================================================================
// Stream Result Utilities
// =============================================================================

/// Get the full text from a streaming result
///
/// ## Example
///
/// ```gleam
/// case api.chat_stream(client, request) {
///   Ok(result) -> io.println(api.stream_text(result))
///   Error(_) -> io.println("Error")
/// }
/// ```
pub fn stream_text(result: StreamResult) -> String {
  result.events
  |> list.filter_map(event_text)
  |> string.join("")
}

/// Extract text from a single streaming event
///
/// ## Example
///
/// ```gleam
/// list.each(result.events, fn(event) {
///   case api.event_text(event) {
///     Ok(text) -> io.print(text)
///     Error(_) -> Nil
///   }
/// })
/// ```
pub fn event_text(event: StreamEvent) -> Result(String, Nil) {
  case event {
    streaming.ContentBlockDeltaEventVariant(delta_event) -> {
      case delta_event.delta {
        streaming.TextContentDelta(text_delta) -> Ok(text_delta.text)
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

/// Check if a streaming result completed successfully
pub fn stream_complete(result: StreamResult) -> Bool {
  list.any(result.events, fn(event) {
    case event {
      streaming.MessageStopEvent -> True
      _ -> False
    }
  })
}

/// Check if a streaming result contains an error
pub fn stream_has_error(result: StreamResult) -> Bool {
  list.any(result.events, fn(event) {
    case event {
      streaming.ErrorEvent(_) -> True
      _ -> False
    }
  })
}

/// Get the message ID from a streaming result
pub fn stream_message_id(result: StreamResult) -> Result(String, Nil) {
  result.events
  |> list.find_map(fn(event) {
    case event {
      streaming.MessageStartEvent(msg) -> Ok(msg.id)
      _ -> Error(Nil)
    }
  })
}

/// Get the model from a streaming result
pub fn stream_model(result: StreamResult) -> Result(String, Nil) {
  result.events
  |> list.find_map(fn(event) {
    case event {
      streaming.MessageStartEvent(msg) -> Ok(msg.model)
      _ -> Error(Nil)
    }
  })
}

// =============================================================================
// Internal Streaming Functions
// =============================================================================

/// Parse SSE body text into streaming events
fn parse_sse_body(body: String) -> Result(StreamResult, StreamError) {
  let state = sse.new_parser_state()
  let parse_result = sse.parse_chunk(state, body)

  let events =
    parse_result.events
    |> list.filter_map(fn(sse_event) {
      case stream_decoder.decode_event(sse_event) {
        Ok(event) -> Ok(event)
        Error(_) -> Error(Nil)
      }
    })

  // Handle any remaining buffered data
  let remaining_events = case sse.flush(parse_result.state) {
    Ok(sse_event) -> {
      case stream_decoder.decode_event(sse_event) {
        Ok(event) -> [event]
        Error(_) -> []
      }
    }
    Error(_) -> []
  }

  Ok(StreamResult(events: list.append(events, remaining_events)))
}

/// Make a streaming HTTP request using gleam_httpc
fn make_streaming_request(
  api_client: Client,
  body: String,
) -> Result(Response(String), AnthropicError) {
  let base_url = api_client.config.base_url
  let full_url = base_url <> messages_endpoint

  // Parse the URL and create request
  use req <- result.try(
    http_request.to(full_url)
    |> result.map_error(fn(_) {
      error.config_error("Invalid URL: " <> full_url)
    }),
  )

  // Set headers and body for streaming
  let req =
    req
    |> http_request.set_method(gleam_http.Post)
    |> http_request.set_header("content-type", "application/json")
    |> http_request.set_header(
      "x-api-key",
      api_key_to_string(api_client.config.api_key),
    )
    |> http_request.set_header("anthropic-version", client.api_version)
    |> http_request.set_header("accept", "text/event-stream")
    |> http_request.set_body(body)

  // Make the request with configured timeout
  httpc.configure()
  |> httpc.timeout(api_client.config.timeout_ms)
  |> httpc.dispatch(req)
  |> result.map_error(fn(err) { http_error_to_anthropic_error(err) })
}

/// Convert httpc error to AnthropicError
fn http_error_to_anthropic_error(err: httpc.HttpError) -> AnthropicError {
  case err {
    httpc.InvalidUtf8Response -> error.http_error("Invalid UTF-8 in response")
    httpc.FailedToConnect(ip4, ip6) ->
      error.network_error(
        "Failed to connect to server (IPv4: "
        <> connect_error_to_string(ip4)
        <> ", IPv6: "
        <> connect_error_to_string(ip6)
        <> ")",
      )
    httpc.ResponseTimeout -> error.timeout_error(0)
  }
}

/// Convert ConnectError to string
fn connect_error_to_string(err: httpc.ConnectError) -> String {
  case err {
    httpc.Posix(code) -> "POSIX error: " <> code
    httpc.TlsAlert(code, detail) -> "TLS alert " <> code <> ": " <> detail
  }
}

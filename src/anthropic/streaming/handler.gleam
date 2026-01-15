//// Streaming HTTP handler for Anthropic API
////
//// This module provides the HTTP handling for streaming responses from the
//// Anthropic Messages API. It processes Server-Sent Events (SSE) and yields
//// parsed streaming events.
////
//// Note: Currently uses synchronous HTTP with SSE parsing. True streaming
//// with real-time chunk processing can be added via Erlang interop if needed.

import anthropic/client.{type Client}
import anthropic/streaming/decoder
import anthropic/streaming/sse
import anthropic/types/error.{type AnthropicError}
import anthropic/types/request as api_request
import anthropic/types/streaming.{type StreamEvent}
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/list
import gleam/result
import gleam/string

// =============================================================================
// Types
// =============================================================================

/// Result of streaming a message
pub type StreamResult {
  StreamResult(
    /// List of parsed streaming events
    events: List(StreamEvent),
  )
}

/// Error during streaming
pub type StreamError {
  /// HTTP error during request
  HttpError(error: AnthropicError)
  /// Error parsing SSE data
  SseParseError(message: String)
  /// Error decoding event JSON
  EventDecodeError(message: String)
  /// API returned an error response
  ApiError(status: Int, body: String)
}

/// Callback function type for processing events as they are parsed
pub type EventCallback =
  fn(StreamEvent) -> Nil

// =============================================================================
// Streaming Functions
// =============================================================================

/// Stream a message request and return all events
///
/// This function sends a streaming request to the Anthropic API,
/// processes the SSE response, and returns all parsed events.
///
/// ## Example
///
/// ```gleam
/// let request = create_request(model, messages, max_tokens)
///   |> with_stream(True)
///
/// case stream_message(client, request) {
///   Ok(result) -> {
///     list.each(result.events, fn(event) {
///       io.println(event_type_string(event))
///     })
///   }
///   Error(err) -> handle_error(err)
/// }
/// ```
pub fn stream_message(
  api_client: Client,
  message_request: api_request.CreateMessageRequest,
) -> Result(StreamResult, StreamError) {
  // Ensure streaming is enabled
  let streaming_request = api_request.with_stream(message_request, True)

  // Encode request to JSON
  let body = api_request.request_to_json_string(streaming_request)

  // Make the HTTP request
  use http_response <- result.try(
    make_streaming_request(api_client, body)
    |> result.map_error(fn(err) { HttpError(error: err) }),
  )

  // Check for error status
  case http_response.status {
    200 -> parse_sse_response(http_response.body)
    status -> Error(ApiError(status: status, body: http_response.body))
  }
}

/// Stream a message request with a callback for each event
///
/// This function is similar to `stream_message` but calls the provided
/// callback function for each event as it is parsed.
///
/// ## Example
///
/// ```gleam
/// stream_message_with_callback(client, request, fn(event) {
///   case event {
///     ContentBlockDeltaEventVariant(delta) -> {
///       case delta.delta {
///         TextContentDelta(text_delta) -> {
///           io.print(text_delta.text)
///         }
///         _ -> Nil
///       }
///     }
///     _ -> Nil
///   }
/// })
/// ```
pub fn stream_message_with_callback(
  api_client: Client,
  message_request: api_request.CreateMessageRequest,
  callback: EventCallback,
) -> Result(StreamResult, StreamError) {
  use result <- result.try(stream_message(api_client, message_request))

  // Call callback for each event
  list.each(result.events, callback)

  Ok(result)
}

// =============================================================================
// Internal Functions
// =============================================================================

/// Make a streaming HTTP request
fn make_streaming_request(
  api_client: Client,
  body: String,
) -> Result(Response(String), AnthropicError) {
  let base_url = api_client.config.base_url
  let full_url = base_url <> client.messages_endpoint

  // Parse the URL and create request
  use req <- result.try(
    request.to(full_url)
    |> result.map_error(fn(_) {
      error.config_error("Invalid URL: " <> full_url)
    }),
  )

  // Set headers and body for streaming
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_header("x-api-key", api_client.config.api_key)
    |> request.set_header("anthropic-version", client.api_version)
    |> request.set_header("accept", "text/event-stream")
    |> request.set_body(body)

  // Make the request with extended timeout for streaming
  httpc.configure()
  |> httpc.timeout(api_client.config.timeout_ms)
  |> httpc.dispatch(req)
  |> result.map_error(fn(err) { http_error_to_anthropic_error(err) })
}

/// Parse an SSE response body into streaming events
fn parse_sse_response(body: String) -> Result(StreamResult, StreamError) {
  let state = sse.new_parser_state()
  let parse_result = sse.parse_chunk(state, body)

  // Decode all parsed SSE events into StreamEvents
  let events =
    parse_result.events
    |> list.filter_map(fn(sse_event) {
      case decoder.decode_event(sse_event) {
        Ok(event) -> Ok(event)
        Error(_) -> Error(Nil)
      }
    })

  // Try to flush any remaining data
  let final_events = case sse.flush(parse_result.state) {
    Ok(sse_event) -> {
      case decoder.decode_event(sse_event) {
        Ok(event) -> list.append(events, [event])
        Error(_) -> events
      }
    }
    Error(_) -> events
  }

  Ok(StreamResult(events: final_events))
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

// =============================================================================
// Event Processing Utilities
// =============================================================================

/// Filter events to only text deltas
pub fn get_text_deltas(events: List(StreamEvent)) -> List(String) {
  events
  |> list.filter_map(fn(event) {
    case event {
      streaming.ContentBlockDeltaEventVariant(delta_event) -> {
        case delta_event.delta {
          streaming.TextContentDelta(text_delta) -> Ok(text_delta.text)
          _ -> Error(Nil)
        }
      }
      _ -> Error(Nil)
    }
  })
}

/// Get the full text from a stream of events
pub fn get_full_text(events: List(StreamEvent)) -> String {
  get_text_deltas(events)
  |> string.join("")
}

/// Get the message ID from events
pub fn get_message_id(events: List(StreamEvent)) -> Result(String, Nil) {
  events
  |> list.find_map(fn(event) {
    case event {
      streaming.MessageStartEvent(msg) -> Ok(msg.id)
      _ -> Error(Nil)
    }
  })
}

/// Get the model from events
pub fn get_model(events: List(StreamEvent)) -> Result(String, Nil) {
  events
  |> list.find_map(fn(event) {
    case event {
      streaming.MessageStartEvent(msg) -> Ok(msg.model)
      _ -> Error(Nil)
    }
  })
}

/// Check if stream completed successfully
pub fn is_complete(events: List(StreamEvent)) -> Bool {
  list.any(events, fn(event) {
    case event {
      streaming.MessageStopEvent -> True
      _ -> False
    }
  })
}

/// Check if stream ended with an error
pub fn has_error(events: List(StreamEvent)) -> Bool {
  list.any(events, fn(event) {
    case event {
      streaming.ErrorEvent(_) -> True
      _ -> False
    }
  })
}

/// Get error from events if present
pub fn get_error(
  events: List(StreamEvent),
) -> Result(streaming.StreamError, Nil) {
  events
  |> list.find_map(fn(event) {
    case event {
      streaming.ErrorEvent(err) -> Ok(err)
      _ -> Error(Nil)
    }
  })
}

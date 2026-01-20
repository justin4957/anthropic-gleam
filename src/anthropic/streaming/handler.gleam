//// Streaming handler for Anthropic API
////
//// This module provides both sans-io functions for SSE parsing and
//// HTTP-integrated streaming using gleam_httpc.
////
//// ## Sans-IO Usage (Recommended)
////
//// Build requests and parse responses without HTTP dependencies:
////
//// ```gleam
//// import anthropic/http
//// import anthropic/streaming/handler
////
//// // Build streaming request
//// let http_request = http.build_streaming_request(api_key, base_url, request)
////
//// // Send with your HTTP client
//// let http_response = my_http_client.send(http_request)
////
//// // Parse SSE response
//// case handler.parse_streaming_response(http_response) {
////   Ok(result) -> handler.get_full_text(result.events)
////   Error(err) -> handle_error(err)
//// }
//// ```
////
//// ## HTTP-Integrated Usage (Uses gleam_httpc)
////
//// For convenience when gleam_httpc is available:
////
//// ```gleam
//// case handler.stream_message(client, request) {
////   Ok(result) -> handler.get_full_text(result.events)
////   Error(err) -> handle_error(err)
//// }
//// ```

import anthropic/client.{type Client}
import anthropic/http
import anthropic/streaming/decoder
import anthropic/streaming/sse
import anthropic/types/error.{type AnthropicError}
import anthropic/types/request as api_request
import anthropic/types/streaming.{type StreamEvent}
import gleam/http as gleam_http
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
// Sans-IO Functions (HTTP-library agnostic)
// =============================================================================

/// Parse an HTTP response body containing SSE events into StreamResult
///
/// This is the sans-io entry point for streaming. Use this with any HTTP client:
///
/// 1. Build a request with `http.build_streaming_request`
/// 2. Send it with your HTTP client
/// 3. Parse the response with this function
///
/// ## Example
///
/// ```gleam
/// let http_response = HttpResponse(status: 200, headers: [], body: sse_body)
/// case parse_streaming_response(http_response) {
///   Ok(result) -> get_full_text(result.events)
///   Error(err) -> handle_error(err)
/// }
/// ```
pub fn parse_streaming_response(
  response: http.HttpResponse,
) -> Result(StreamResult, StreamError) {
  case response.status {
    200 -> parse_sse_body(response.body)
    status -> Error(ApiError(status: status, body: response.body))
  }
}

/// Parse SSE body text into streaming events
///
/// Use this for even more control - if you already have the SSE text
/// and have handled status codes yourself.
pub fn parse_sse_body(body: String) -> Result(StreamResult, StreamError) {
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

/// Parse a single SSE chunk and return events plus updated state
///
/// For incremental streaming, use this to process chunks as they arrive:
///
/// ```gleam
/// let state = sse.new_parser_state()
///
/// // As each chunk arrives from your HTTP client:
/// let #(events, new_state) = parse_sse_chunk(state, chunk)
/// list.each(events, process_event)
/// // Continue with new_state for next chunk
/// ```
pub fn parse_sse_chunk(
  state: sse.SseParserState,
  chunk: String,
) -> #(List(StreamEvent), sse.SseParserState) {
  let parse_result = sse.parse_chunk(state, chunk)

  let events =
    parse_result.events
    |> list.filter_map(fn(sse_event) {
      case decoder.decode_event(sse_event) {
        Ok(event) -> Ok(event)
        Error(_) -> Error(Nil)
      }
    })

  #(events, parse_result.state)
}

// =============================================================================
// HTTP-Integrated Functions (Uses gleam_httpc)
// =============================================================================

/// Stream a message request and return all events
///
/// This function uses gleam_httpc directly. For HTTP-library independence,
/// use `http.build_streaming_request` + `parse_streaming_response` instead.
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
    200 -> parse_sse_body(http_response.body)
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
  use stream_result <- result.try(stream_message(api_client, message_request))

  // Call callback for each event
  list.each(stream_result.events, callback)

  Ok(stream_result)
}

// =============================================================================
// Internal Functions
// =============================================================================

/// Make a streaming HTTP request using gleam_httpc
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
    |> request.set_method(gleam_http.Post)
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
// Event Processing Utilities (Sans-IO - work with any event list)
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

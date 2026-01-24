//// Streaming handler for Anthropic API
////
//// This module provides sans-io functions for parsing Server-Sent Events (SSE)
//// from the Anthropic streaming API. The design follows the sans-io pattern,
//// allowing you to use any HTTP client that supports streaming.
////
//// ## Recommended: Use `api.chat_stream`
////
//// For most use cases, use `api.chat_stream` from the main API module:
////
//// ```gleam
//// import anthropic/api
//// import anthropic/client
//// import anthropic/types/request
//// import anthropic/types/message.{user_message}
////
//// let assert Ok(client) = client.init()
//// let req = request.new("claude-sonnet-4-20250514", [user_message("Hello!")], 1024)
////
//// case api.chat_stream(client, req) {
////   Ok(result) -> io.println(api.stream_text(result))
////   Error(err) -> handle_error(err)
//// }
//// ```
////
//// ## True Real-Time Streaming (Sans-IO)
////
//// For true real-time streaming where you process events as they arrive,
//// use the incremental parsing functions with your own streaming HTTP client:
////
//// ```gleam
//// import anthropic/http
//// import anthropic/streaming/handler.{
////   new_streaming_state, process_chunk, finalize_stream
//// }
////
//// // 1. Build the streaming request
//// let http_request = http.build_streaming_request(api_key, base_url, request)
////
//// // 2. Start streaming with your HTTP client that supports chunked responses
//// // (e.g., using Erlang's httpc with stream option, or any other client)
////
//// // 3. Initialize streaming state
//// let state = new_streaming_state()
////
//// // 4. As each chunk arrives from your HTTP client, process it:
//// let #(events, new_state) = process_chunk(state, chunk)
////
//// // 5. Handle events in real-time as they arrive
//// list.each(events, fn(event) {
////   case handler.get_event_text(event) {
////     Ok(text) -> io.print(text)  // Print immediately!
////     Error(_) -> Nil
////   }
//// })
////
//// // 6. Continue with new_state for next chunk...
////
//// // 7. When stream ends, finalize to get any remaining events
//// let final_events = finalize_stream(state)
//// ```
////
//// ## Batch Mode (Deprecated)
////
//// The batch functions `stream_message` and `stream_message_with_callback` in
//// this module are deprecated. Use `api.chat_stream` and
//// `api.chat_stream_with_callback` instead for a unified API.
////
//// **Note**: Batch mode waits for the complete response before returning.
//// Use sans-io incremental parsing for true real-time streaming.

import anthropic/client.{type Client}
import anthropic/config.{api_key_to_string}
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
import gleam/option.{type Option, None}
import gleam/result
import gleam/string

// =============================================================================
// Types
// =============================================================================

/// State for incremental streaming (sans-io)
///
/// Use this to track parsing state across multiple chunks when implementing
/// real-time streaming with your own HTTP client.
pub type StreamingState {
  StreamingState(
    /// Internal SSE parser state
    sse_state: sse.SseParserState,
    /// Accumulated events (for building final result)
    events: List(StreamEvent),
    /// Whether the stream has completed
    completed: Bool,
    /// Error if one occurred
    error: Option(StreamError),
  )
}

/// Result of streaming a message (batch mode)
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
// Sans-IO Incremental Streaming (True Real-Time)
// =============================================================================

/// Create a new streaming state for incremental parsing
///
/// Use this when implementing true real-time streaming with your own HTTP client.
///
/// ## Example
///
/// ```gleam
/// let state = new_streaming_state()
///
/// // As chunks arrive from your streaming HTTP client:
/// let #(events, new_state) = process_chunk(state, chunk)
/// list.each(events, handle_event_immediately)
/// ```
pub fn new_streaming_state() -> StreamingState {
  StreamingState(
    sse_state: sse.new_parser_state(),
    events: [],
    completed: False,
    error: None,
  )
}

/// Process a chunk of SSE data and return parsed events
///
/// This is the core function for real-time streaming. Call it each time
/// you receive a chunk from your streaming HTTP client.
///
/// Returns a tuple of:
/// - List of events parsed from this chunk (process these immediately!)
/// - Updated state to use for the next chunk
///
/// ## Example
///
/// ```gleam
/// // In your streaming HTTP callback:
/// fn on_chunk(state: StreamingState, chunk: String) -> StreamingState {
///   let #(events, new_state) = process_chunk(state, chunk)
///
///   // Process events immediately as they arrive
///   list.each(events, fn(event) {
///     case get_event_text(event) {
///       Ok(text) -> io.print(text)  // Real-time output!
///       Error(_) -> Nil
///     }
///   })
///
///   new_state
/// }
/// ```
pub fn process_chunk(
  state: StreamingState,
  chunk: String,
) -> #(List(StreamEvent), StreamingState) {
  let parse_result = sse.parse_chunk(state.sse_state, chunk)

  let events =
    parse_result.events
    |> list.filter_map(fn(sse_event) {
      case decoder.decode_event(sse_event) {
        Ok(event) -> Ok(event)
        Error(_) -> Error(Nil)
      }
    })

  // Check if stream completed
  let completed =
    list.any(events, fn(event) {
      case event {
        streaming.MessageStopEvent -> True
        _ -> False
      }
    })

  // Check for errors
  let error =
    list.find_map(events, fn(event) {
      case event {
        streaming.ErrorEvent(err) ->
          Ok(SseParseError(message: err.error_type <> ": " <> err.message))
        _ -> Error(Nil)
      }
    })
    |> option.from_result

  let new_state =
    StreamingState(
      sse_state: parse_result.state,
      events: list.append(state.events, events),
      completed: completed,
      error: error,
    )

  #(events, new_state)
}

/// Finalize the stream and get any remaining events
///
/// Call this when your HTTP client signals the stream has ended.
/// Returns any events that were buffered but not yet emitted.
pub fn finalize_stream(state: StreamingState) -> List(StreamEvent) {
  case sse.flush(state.sse_state) {
    Ok(sse_event) -> {
      case decoder.decode_event(sse_event) {
        Ok(event) -> [event]
        Error(_) -> []
      }
    }
    Error(_) -> []
  }
}

/// Check if the stream has completed successfully
pub fn is_stream_complete(state: StreamingState) -> Bool {
  state.completed
}

/// Check if the stream encountered an error
pub fn has_stream_error(state: StreamingState) -> Bool {
  option.is_some(state.error)
}

/// Get the error from the stream if one occurred
pub fn get_stream_error(state: StreamingState) -> Option(StreamError) {
  state.error
}

/// Get all accumulated events from the streaming state
pub fn get_accumulated_events(state: StreamingState) -> List(StreamEvent) {
  state.events
}

/// Build a StreamResult from the final streaming state
pub fn build_stream_result(state: StreamingState) -> StreamResult {
  StreamResult(events: state.events)
}

// =============================================================================
// Sans-IO Batch Parsing (Parse Complete Response)
// =============================================================================

/// Parse an HTTP response body containing SSE events into StreamResult
///
/// This is for batch parsing of a complete response. For real-time streaming,
/// use `new_streaming_state` + `process_chunk` instead.
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

/// Parse SSE body text into streaming events (batch mode)
///
/// Use this for batch parsing when you have the complete SSE text.
/// For real-time streaming, use `process_chunk` instead.
pub fn parse_sse_body(body: String) -> Result(StreamResult, StreamError) {
  let state = new_streaming_state()
  let #(events, final_state) = process_chunk(state, body)
  let remaining = finalize_stream(final_state)
  Ok(StreamResult(events: list.append(events, remaining)))
}

/// Parse a single SSE chunk and return events plus updated SSE state
///
/// Lower-level function that works directly with SSE parser state.
/// Consider using `process_chunk` with `StreamingState` for a higher-level API.
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
// HTTP-Integrated Functions (Batch Mode - Uses gleam_httpc)
// =============================================================================

/// Stream a message request and return all events (batch mode)
///
/// @deprecated Use `api.chat_stream` instead for a unified streaming API
///
/// **Note**: This function collects ALL events before returning. It does NOT
/// provide true real-time streaming. For real-time streaming, use the sans-io
/// functions (`new_streaming_state`, `process_chunk`) with a streaming HTTP client.
///
/// ## Example
///
/// ```gleam
/// // Prefer using api.chat_stream instead:
/// case api.chat_stream(client, request) {
///   Ok(result) -> api.stream_text(result)
///   Error(err) -> handle_error(err)
/// }
/// ```
@deprecated("Use api.chat_stream instead")
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

/// Stream a message request with a callback for each event (batch mode)
///
/// @deprecated Use `api.chat_stream_with_callback` instead for a unified streaming API
///
/// **Note**: Despite the callback, this function collects ALL events before
/// calling the callbacks. It does NOT provide true real-time streaming.
/// For real-time streaming, use the sans-io functions with a streaming HTTP client.
///
/// ## Example
///
/// ```gleam
/// // Prefer using api.chat_stream_with_callback instead:
/// api.chat_stream_with_callback(client, request, fn(event) {
///   case api.event_text(event) {
///     Ok(text) -> io.print(text)
///     Error(_) -> Nil
///   }
/// })
/// ```
@deprecated("Use api.chat_stream_with_callback instead")
pub fn stream_message_with_callback(
  api_client: Client,
  message_request: api_request.CreateMessageRequest,
  callback: EventCallback,
) -> Result(StreamResult, StreamError) {
  use stream_result <- result.try(stream_message(api_client, message_request))

  // Call callback for each event (after all collected)
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
    |> request.set_header(
      "x-api-key",
      api_key_to_string(api_client.config.api_key),
    )
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

/// Extract text from a single event if it contains text content
///
/// Useful for real-time streaming to print text as it arrives.
///
/// ## Example
///
/// ```gleam
/// list.each(events, fn(event) {
///   case get_event_text(event) {
///     Ok(text) -> io.print(text)
///     Error(_) -> Nil
///   }
/// })
/// ```
pub fn get_event_text(event: StreamEvent) -> Result(String, Nil) {
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

/// Filter events to only text deltas
pub fn get_text_deltas(events: List(StreamEvent)) -> List(String) {
  events
  |> list.filter_map(get_event_text)
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

/// Check if stream completed successfully (from event list)
pub fn is_complete(events: List(StreamEvent)) -> Bool {
  list.any(events, fn(event) {
    case event {
      streaming.MessageStopEvent -> True
      _ -> False
    }
  })
}

/// Check if stream ended with an error (from event list)
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

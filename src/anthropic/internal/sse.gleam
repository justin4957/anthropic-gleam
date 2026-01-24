//// Server-Sent Events (SSE) parser for Anthropic streaming responses
////
//// This module provides parsing utilities for SSE format used by the
//// Anthropic streaming API. It handles multi-line data fields, event types,
//// keepalives, and malformed events gracefully.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// =============================================================================
// Types
// =============================================================================

/// A parsed SSE event
pub type SseEvent {
  SseEvent(
    /// The event type (e.g., "message_start", "content_block_delta")
    event_type: Option(String),
    /// The event data (JSON string)
    data: Option(String),
    /// Event ID (rarely used)
    id: Option(String),
    /// Retry interval in milliseconds (rarely used)
    retry: Option(Int),
  )
}

/// Parser state for accumulating SSE events
pub type SseParserState {
  SseParserState(
    /// Current event type being parsed
    current_event_type: Option(String),
    /// Accumulated data lines
    current_data: List(String),
    /// Current event ID
    current_id: Option(String),
    /// Current retry value
    current_retry: Option(Int),
    /// Buffer for incomplete lines
    buffer: String,
  )
}

/// Result of parsing SSE data
pub type SseParseResult {
  SseParseResult(
    /// Parsed events
    events: List(SseEvent),
    /// Updated parser state
    state: SseParserState,
  )
}

/// SSE parsing error
pub type SseError {
  /// Invalid field format
  InvalidField(line: String)
  /// Empty event (no data)
  EmptyEvent
  /// Invalid retry value
  InvalidRetry(value: String)
}

// =============================================================================
// Parser State Management
// =============================================================================

/// Create a new parser state
pub fn new_parser_state() -> SseParserState {
  SseParserState(
    current_event_type: None,
    current_data: [],
    current_id: None,
    current_retry: None,
    buffer: "",
  )
}

/// Reset parser state for next event (keeps buffer)
pub fn reset_event_state(state: SseParserState) -> SseParserState {
  SseParserState(
    current_event_type: None,
    current_data: [],
    current_id: None,
    current_retry: None,
    buffer: state.buffer,
  )
}

// =============================================================================
// Single Event Parsing
// =============================================================================

/// Parse a single SSE event from a complete event block (lines separated by \n)
pub fn parse_event(event_block: String) -> Result(SseEvent, SseError) {
  let lines = string.split(event_block, "\n")
  parse_event_lines(lines)
}

/// Parse SSE event from a list of lines
pub fn parse_event_lines(lines: List(String)) -> Result(SseEvent, SseError) {
  let initial_state =
    SseParserState(
      current_event_type: None,
      current_data: [],
      current_id: None,
      current_retry: None,
      buffer: "",
    )

  let final_state =
    list.fold(lines, initial_state, fn(state, line) { parse_line(state, line) })

  build_event(final_state)
}

/// Parse a single line and update parser state
pub fn parse_line(state: SseParserState, line: String) -> SseParserState {
  // Skip empty lines (they mark event boundaries in stream context)
  case string.trim(line) {
    "" -> state
    _ -> parse_field_line(state, line)
  }
}

/// Parse a field line (field: value format)
fn parse_field_line(state: SseParserState, line: String) -> SseParserState {
  // Handle comment lines (start with :)
  case string.starts_with(line, ":") {
    True -> state
    False -> {
      // Split on first colon
      case string.split_once(line, ":") {
        Ok(#(field, value)) -> {
          // Remove leading space from value if present
          let trimmed_value = case string.starts_with(value, " ") {
            True -> string.drop_start(value, 1)
            False -> value
          }
          apply_field(state, field, trimmed_value)
        }
        Error(_) -> {
          // Line without colon - treat as field with empty value
          apply_field(state, line, "")
        }
      }
    }
  }
}

/// Apply a parsed field to the parser state
fn apply_field(
  state: SseParserState,
  field: String,
  value: String,
) -> SseParserState {
  case field {
    "event" -> SseParserState(..state, current_event_type: Some(value))
    "data" ->
      SseParserState(
        ..state,
        current_data: list.append(state.current_data, [value]),
      )
    "id" -> SseParserState(..state, current_id: Some(value))
    "retry" -> {
      case parse_int(value) {
        Ok(n) -> SseParserState(..state, current_retry: Some(n))
        Error(_) -> state
      }
    }
    _ -> state
  }
}

/// Build an SseEvent from the current parser state
fn build_event(state: SseParserState) -> Result(SseEvent, SseError) {
  // Join data lines with newlines (SSE spec)
  let data = case state.current_data {
    [] -> None
    lines -> Some(string.join(lines, "\n"))
  }

  // An event with no data and no event type is empty/keepalive
  case data, state.current_event_type {
    None, None -> Error(EmptyEvent)
    _, _ ->
      Ok(SseEvent(
        event_type: state.current_event_type,
        data: data,
        id: state.current_id,
        retry: state.current_retry,
      ))
  }
}

// =============================================================================
// Stream Parsing
// =============================================================================

/// Parse a chunk of SSE data, returning parsed events and updated state
///
/// This function handles partial events that span multiple chunks by
/// maintaining a buffer in the parser state.
pub fn parse_chunk(state: SseParserState, chunk: String) -> SseParseResult {
  // Combine buffer with new chunk
  let full_data = state.buffer <> chunk

  // Split on double newlines (event boundaries)
  let parts = string.split(full_data, "\n\n")

  // Process all complete events (all but the last part)
  let #(events, remaining) = case parts {
    [] -> #([], "")
    [single] -> #([], single)
    _ -> {
      let complete_parts = list.take(parts, list.length(parts) - 1)
      let last_part = list.last(parts) |> result.unwrap("")

      let parsed_events =
        complete_parts
        |> list.filter_map(fn(part) {
          case string.trim(part) {
            "" -> Error(Nil)
            trimmed -> {
              case parse_event(trimmed) {
                Ok(event) -> Ok(event)
                Error(_) -> Error(Nil)
              }
            }
          }
        })

      #(parsed_events, last_part)
    }
  }

  SseParseResult(
    events: events,
    state: SseParserState(..new_parser_state(), buffer: remaining),
  )
}

/// Flush any remaining data in the buffer as a final event
pub fn flush(state: SseParserState) -> Result(SseEvent, SseError) {
  case string.trim(state.buffer) {
    "" -> Error(EmptyEvent)
    data -> parse_event(data)
  }
}

// =============================================================================
// Utility Functions
// =============================================================================

/// Check if an SSE event is a keepalive/ping
pub fn is_keepalive(event: SseEvent) -> Bool {
  case event.event_type, event.data {
    None, None -> True
    Some("ping"), _ -> True
    _, _ -> False
  }
}

/// Get the event type as a string, defaulting to "message" if not specified
pub fn get_event_type(event: SseEvent) -> String {
  option.unwrap(event.event_type, "message")
}

/// Get the data as a string, defaulting to empty string
pub fn get_data(event: SseEvent) -> String {
  option.unwrap(event.data, "")
}

/// Create an SSE event (primarily for testing)
pub fn sse_event(event_type: Option(String), data: Option(String)) -> SseEvent {
  SseEvent(event_type: event_type, data: data, id: None, retry: None)
}

/// Create an SSE event with all fields
pub fn sse_event_full(
  event_type: Option(String),
  data: Option(String),
  id: Option(String),
  retry: Option(Int),
) -> SseEvent {
  SseEvent(event_type: event_type, data: data, id: id, retry: retry)
}

// =============================================================================
// FFI Helpers
// =============================================================================

/// Parse an integer from a string
fn parse_int(str: String) -> Result(Int, Nil) {
  case int_from_string(str) {
    Ok(n) -> Ok(n)
    Error(_) -> Error(Nil)
  }
}

@external(erlang, "gleam_stdlib", "parse_int")
fn int_from_string(str: String) -> Result(Int, Nil)

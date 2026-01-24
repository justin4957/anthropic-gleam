//// Streaming event types for the Anthropic Messages API
////
//// This module defines types for Server-Sent Events (SSE) from the streaming API,
//// including message_start, content_block_start, content_block_delta,
//// content_block_stop, message_delta, message_stop, ping, and error events.

import anthropic/message.{type ContentBlock, type Role}
import anthropic/request.{type StopReason, type Usage}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

// =============================================================================
// Delta Types
// =============================================================================

/// Delta type for text content streaming
pub type TextDelta {
  TextDelta(
    /// The text fragment being streamed
    text: String,
  )
}

/// Delta type for tool input JSON streaming
pub type InputJsonDelta {
  InputJsonDelta(
    /// Partial JSON string for tool input
    partial_json: String,
  )
}

/// Union type for content block deltas
pub type ContentBlockDelta {
  /// Text content delta
  TextContentDelta(delta: TextDelta)
  /// Tool input JSON delta
  InputJsonContentDelta(delta: InputJsonDelta)
}

// =============================================================================
// Message Start Event
// =============================================================================

/// Initial message information sent at stream start
pub type MessageStart {
  MessageStart(
    /// Unique identifier for this message
    id: String,
    /// Object type, always "message"
    message_type: String,
    /// Role of the response, always "assistant"
    role: Role,
    /// Model that is generating the response
    model: String,
    /// Initial usage information (input tokens)
    usage: Usage,
  )
}

// =============================================================================
// Content Block Start Event
// =============================================================================

/// Information about a content block starting
pub type ContentBlockStart {
  ContentBlockStart(
    /// Index of this content block in the message
    index: Int,
    /// The initial content block (with empty/partial content)
    content_block: ContentBlock,
  )
}

// =============================================================================
// Content Block Delta Event
// =============================================================================

/// Delta update for a content block
pub type ContentBlockDeltaEvent {
  ContentBlockDeltaEvent(
    /// Index of the content block being updated
    index: Int,
    /// The delta update
    delta: ContentBlockDelta,
  )
}

// =============================================================================
// Content Block Stop Event
// =============================================================================

/// Marks the end of a content block
pub type ContentBlockStop {
  ContentBlockStop(
    /// Index of the content block that ended
    index: Int,
  )
}

// =============================================================================
// Message Delta Event
// =============================================================================

/// Delta update for message-level information
pub type MessageDelta {
  MessageDelta(
    /// The reason generation stopped (if applicable)
    stop_reason: Option(StopReason),
    /// The stop sequence that triggered stopping (if applicable)
    stop_sequence: Option(String),
  )
}

/// Usage information in message delta
pub type MessageDeltaUsage {
  MessageDeltaUsage(
    /// Number of output tokens generated
    output_tokens: Int,
  )
}

/// Full message delta event with usage
pub type MessageDeltaEvent {
  MessageDeltaEvent(
    /// The delta update
    delta: MessageDelta,
    /// Updated usage information
    usage: MessageDeltaUsage,
  )
}

// =============================================================================
// Error Event
// =============================================================================

/// Error information from a streaming error event
pub type StreamError {
  StreamError(
    /// Error type string
    error_type: String,
    /// Error message
    message: String,
  )
}

// =============================================================================
// Stream Event (Union Type)
// =============================================================================

/// All possible streaming events from the API
pub type StreamEvent {
  /// Initial message information
  MessageStartEvent(message: MessageStart)
  /// Start of a content block
  ContentBlockStartEvent(content_block_start: ContentBlockStart)
  /// Delta update for a content block
  ContentBlockDeltaEventVariant(content_block_delta: ContentBlockDeltaEvent)
  /// End of a content block
  ContentBlockStopEvent(content_block_stop: ContentBlockStop)
  /// Delta update for message-level information
  MessageDeltaEventVariant(message_delta: MessageDeltaEvent)
  /// End of the message
  MessageStopEvent
  /// Keepalive ping
  PingEvent
  /// Error during streaming
  ErrorEvent(error: StreamError)
}

// =============================================================================
// Event Type String Conversion
// =============================================================================

/// Get the event type string for a StreamEvent
pub fn event_type_string(event: StreamEvent) -> String {
  case event {
    MessageStartEvent(_) -> "message_start"
    ContentBlockStartEvent(_) -> "content_block_start"
    ContentBlockDeltaEventVariant(_) -> "content_block_delta"
    ContentBlockStopEvent(_) -> "content_block_stop"
    MessageDeltaEventVariant(_) -> "message_delta"
    MessageStopEvent -> "message_stop"
    PingEvent -> "ping"
    ErrorEvent(_) -> "error"
  }
}

/// Parse an event type string
pub fn event_type_from_string(str: String) -> Result(String, String) {
  case str {
    "message_start"
    | "content_block_start"
    | "content_block_delta"
    | "content_block_stop"
    | "message_delta"
    | "message_stop"
    | "ping"
    | "error" -> Ok(str)
    _ -> Error("Unknown event type: " <> str)
  }
}

// =============================================================================
// JSON Encoding
// =============================================================================

/// Encode a TextDelta to JSON
pub fn text_delta_to_json(delta: TextDelta) -> Json {
  json.object([
    #("type", json.string("text_delta")),
    #("text", json.string(delta.text)),
  ])
}

/// Encode an InputJsonDelta to JSON
pub fn input_json_delta_to_json(delta: InputJsonDelta) -> Json {
  json.object([
    #("type", json.string("input_json_delta")),
    #("partial_json", json.string(delta.partial_json)),
  ])
}

/// Encode a ContentBlockDelta to JSON
pub fn content_block_delta_to_json(delta: ContentBlockDelta) -> Json {
  case delta {
    TextContentDelta(d) -> text_delta_to_json(d)
    InputJsonContentDelta(d) -> input_json_delta_to_json(d)
  }
}

/// Encode a StreamError to JSON
pub fn stream_error_to_json(error: StreamError) -> Json {
  json.object([
    #("type", json.string(error.error_type)),
    #("message", json.string(error.message)),
  ])
}

// =============================================================================
// Constructors
// =============================================================================

/// Create a TextDelta
pub fn text_delta(text: String) -> TextDelta {
  TextDelta(text: text)
}

/// Create an InputJsonDelta
pub fn input_json_delta(partial_json: String) -> InputJsonDelta {
  InputJsonDelta(partial_json: partial_json)
}

/// Create a MessageStart
pub fn message_start(
  id: String,
  role: Role,
  model: String,
  input_tokens: Int,
) -> MessageStart {
  MessageStart(
    id: id,
    message_type: "message",
    role: role,
    model: model,
    usage: request.Usage(input_tokens: input_tokens, output_tokens: 0),
  )
}

/// Create a ContentBlockStart for a text block
pub fn text_block_start(index: Int) -> ContentBlockStart {
  ContentBlockStart(index: index, content_block: message.TextBlock(text: ""))
}

/// Create a ContentBlockStart for a tool use block
pub fn tool_use_block_start(
  index: Int,
  id: String,
  name: String,
) -> ContentBlockStart {
  ContentBlockStart(
    index: index,
    content_block: message.ToolUseBlock(id: id, name: name, input: ""),
  )
}

/// Create a ContentBlockDeltaEvent for text
pub fn text_delta_event(index: Int, text: String) -> ContentBlockDeltaEvent {
  ContentBlockDeltaEvent(
    index: index,
    delta: TextContentDelta(TextDelta(text: text)),
  )
}

/// Create a ContentBlockDeltaEvent for tool input JSON
pub fn input_json_delta_event(
  index: Int,
  partial_json: String,
) -> ContentBlockDeltaEvent {
  ContentBlockDeltaEvent(
    index: index,
    delta: InputJsonContentDelta(InputJsonDelta(partial_json: partial_json)),
  )
}

/// Create a ContentBlockStop
pub fn content_block_stop(index: Int) -> ContentBlockStop {
  ContentBlockStop(index: index)
}

/// Create a MessageDeltaEvent
pub fn message_delta_event(
  stop_reason: Option(StopReason),
  stop_sequence: Option(String),
  output_tokens: Int,
) -> MessageDeltaEvent {
  MessageDeltaEvent(
    delta: MessageDelta(stop_reason: stop_reason, stop_sequence: stop_sequence),
    usage: MessageDeltaUsage(output_tokens: output_tokens),
  )
}

/// Create a StreamError
pub fn stream_error(error_type: String, message: String) -> StreamError {
  StreamError(error_type: error_type, message: message)
}

// =============================================================================
// Utility Functions
// =============================================================================

/// Check if an event is a terminal event (message_stop or error)
pub fn is_terminal_event(event: StreamEvent) -> Bool {
  case event {
    MessageStopEvent -> True
    ErrorEvent(_) -> True
    _ -> False
  }
}

/// Get the text from a content block delta, if it's a text delta
pub fn get_delta_text(delta: ContentBlockDelta) -> Option(String) {
  case delta {
    TextContentDelta(d) -> Some(d.text)
    InputJsonContentDelta(_) -> None
  }
}

/// Get the partial JSON from a content block delta, if it's an input JSON delta
pub fn get_delta_json(delta: ContentBlockDelta) -> Option(String) {
  case delta {
    TextContentDelta(_) -> None
    InputJsonContentDelta(d) -> Some(d.partial_json)
  }
}

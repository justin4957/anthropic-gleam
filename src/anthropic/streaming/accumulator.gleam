//// Stream accumulator for building complete messages from streaming events
////
//// This module provides utilities for accumulating streaming events into
//// a complete message response. It tracks content blocks, handles deltas,
//// and produces the final message with usage statistics.

import anthropic/message.{type ContentBlock, type Role, TextBlock, ToolUseBlock}
import anthropic/request.{
  type CreateMessageResponse, type StopReason, CreateMessageResponse, Usage,
}
import anthropic/streaming.{
  type ContentBlockDelta, type MessageDeltaEvent, type MessageStart,
  type StreamEvent, ContentBlockDeltaEventVariant, ContentBlockStartEvent,
  ContentBlockStopEvent, ErrorEvent, InputJsonContentDelta,
  MessageDeltaEventVariant, MessageStartEvent, MessageStopEvent, PingEvent,
  TextContentDelta,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

// =============================================================================
// Accumulator State
// =============================================================================

/// State for accumulating streaming events into a complete message
pub type AccumulatorState {
  AccumulatorState(
    /// Message ID
    id: Option(String),
    /// Message type
    message_type: Option(String),
    /// Role of the response
    role: Option(Role),
    /// Model that generated the response
    model: Option(String),
    /// Content blocks being accumulated (index -> accumulated content)
    content_blocks: Dict(Int, ContentBlockState),
    /// Final stop reason
    stop_reason: Option(StopReason),
    /// Final stop sequence
    stop_sequence: Option(String),
    /// Input tokens from message_start
    input_tokens: Int,
    /// Output tokens from message_delta
    output_tokens: Int,
    /// Whether the stream is complete
    is_complete: Bool,
    /// Error if one occurred
    error: Option(streaming.StreamError),
  )
}

/// State for a content block being accumulated
pub type ContentBlockState {
  /// Text block being accumulated
  TextBlockState(text: String)
  /// Tool use block being accumulated
  ToolUseBlockState(id: String, name: String, input: String)
}

// =============================================================================
// Accumulator Functions
// =============================================================================

/// Create a new accumulator state
pub fn new() -> AccumulatorState {
  AccumulatorState(
    id: None,
    message_type: None,
    role: None,
    model: None,
    content_blocks: dict.new(),
    stop_reason: None,
    stop_sequence: None,
    input_tokens: 0,
    output_tokens: 0,
    is_complete: False,
    error: None,
  )
}

/// Process a single event and update accumulator state
pub fn process_event(
  state: AccumulatorState,
  event: StreamEvent,
) -> AccumulatorState {
  case event {
    MessageStartEvent(msg) -> handle_message_start(state, msg)
    ContentBlockStartEvent(start) -> handle_content_block_start(state, start)
    ContentBlockDeltaEventVariant(delta) ->
      handle_content_block_delta(state, delta)
    ContentBlockStopEvent(_) -> state
    MessageDeltaEventVariant(delta) -> handle_message_delta(state, delta)
    MessageStopEvent -> AccumulatorState(..state, is_complete: True)
    PingEvent -> state
    ErrorEvent(err) -> AccumulatorState(..state, error: Some(err))
  }
}

/// Process multiple events and return final state
pub fn process_events(events: List(StreamEvent)) -> AccumulatorState {
  list.fold(events, new(), process_event)
}

/// Process events with a callback for each event
pub fn process_events_with_callback(
  events: List(StreamEvent),
  callback: fn(StreamEvent, AccumulatorState) -> Nil,
) -> AccumulatorState {
  list.fold(events, new(), fn(state, event) {
    let new_state = process_event(state, event)
    callback(event, new_state)
    new_state
  })
}

// =============================================================================
// Event Handlers
// =============================================================================

/// Handle message_start event
fn handle_message_start(
  state: AccumulatorState,
  msg: MessageStart,
) -> AccumulatorState {
  AccumulatorState(
    ..state,
    id: Some(msg.id),
    message_type: Some(msg.message_type),
    role: Some(msg.role),
    model: Some(msg.model),
    input_tokens: msg.usage.input_tokens,
  )
}

/// Handle content_block_start event
fn handle_content_block_start(
  state: AccumulatorState,
  start: streaming.ContentBlockStart,
) -> AccumulatorState {
  let block_state = case start.content_block {
    TextBlock(text: text) -> TextBlockState(text: text)
    ToolUseBlock(id: id, name: name, input: input) ->
      ToolUseBlockState(id: id, name: name, input: input)
    _ -> TextBlockState(text: "")
  }

  AccumulatorState(
    ..state,
    content_blocks: dict.insert(state.content_blocks, start.index, block_state),
  )
}

/// Handle content_block_delta event
fn handle_content_block_delta(
  state: AccumulatorState,
  delta: streaming.ContentBlockDeltaEvent,
) -> AccumulatorState {
  let updated_blocks = case dict.get(state.content_blocks, delta.index) {
    Ok(block_state) -> {
      let new_block_state = apply_delta(block_state, delta.delta)
      dict.insert(state.content_blocks, delta.index, new_block_state)
    }
    Error(_) -> {
      // Block not found - create based on delta type
      let new_block_state = case delta.delta {
        TextContentDelta(text_delta) -> TextBlockState(text: text_delta.text)
        InputJsonContentDelta(json_delta) ->
          ToolUseBlockState(id: "", name: "", input: json_delta.partial_json)
      }
      dict.insert(state.content_blocks, delta.index, new_block_state)
    }
  }

  AccumulatorState(..state, content_blocks: updated_blocks)
}

/// Apply a delta to a content block state
fn apply_delta(
  block_state: ContentBlockState,
  delta: ContentBlockDelta,
) -> ContentBlockState {
  case block_state, delta {
    TextBlockState(text), TextContentDelta(text_delta) ->
      TextBlockState(text: text <> text_delta.text)
    ToolUseBlockState(id, name, input), InputJsonContentDelta(json_delta) ->
      ToolUseBlockState(
        id: id,
        name: name,
        input: input <> json_delta.partial_json,
      )
    _, _ -> block_state
  }
}

/// Handle message_delta event
fn handle_message_delta(
  state: AccumulatorState,
  delta: MessageDeltaEvent,
) -> AccumulatorState {
  AccumulatorState(
    ..state,
    stop_reason: delta.delta.stop_reason,
    stop_sequence: delta.delta.stop_sequence,
    output_tokens: delta.usage.output_tokens,
  )
}

// =============================================================================
// Building Final Response
// =============================================================================

/// Build a CreateMessageResponse from the accumulated state
pub fn build_response(
  state: AccumulatorState,
) -> Result(CreateMessageResponse, String) {
  use id <- require_some(state.id, "Missing message ID")
  use role <- require_some(state.role, "Missing role")
  use model <- require_some(state.model, "Missing model")

  let content = build_content_blocks(state.content_blocks)

  Ok(CreateMessageResponse(
    id: id,
    response_type: option.unwrap(state.message_type, "message"),
    role: role,
    content: content,
    model: model,
    stop_reason: state.stop_reason,
    stop_sequence: state.stop_sequence,
    usage: Usage(
      input_tokens: state.input_tokens,
      output_tokens: state.output_tokens,
    ),
  ))
}

/// Build content blocks from accumulated state
fn build_content_blocks(
  blocks: Dict(Int, ContentBlockState),
) -> List(ContentBlock) {
  blocks
  |> dict.to_list
  |> list.sort(fn(a, b) {
    let #(index_a, _) = a
    let #(index_b, _) = b
    case index_a < index_b {
      True -> order.Lt
      False ->
        case index_a > index_b {
          True -> order.Gt
          False -> order.Eq
        }
    }
  })
  |> list.map(fn(pair) {
    let #(_, block_state) = pair
    case block_state {
      TextBlockState(text) -> TextBlock(text: text)
      ToolUseBlockState(id, name, input) ->
        ToolUseBlock(id: id, name: name, input: input)
    }
  })
}

/// Helper for requiring Option values with use syntax
fn require_some(
  opt: Option(a),
  error_msg: String,
  next: fn(a) -> Result(b, String),
) -> Result(b, String) {
  case opt {
    Some(value) -> next(value)
    None -> Error(error_msg)
  }
}

// =============================================================================
// Convenience Functions
// =============================================================================

/// Accumulate events and build final response
pub fn accumulate(
  events: List(StreamEvent),
) -> Result(CreateMessageResponse, String) {
  let state = process_events(events)
  build_response(state)
}

/// Get the accumulated text so far
pub fn get_accumulated_text(state: AccumulatorState) -> String {
  state.content_blocks
  |> dict.values
  |> list.filter_map(fn(block) {
    case block {
      TextBlockState(text) -> Ok(text)
      _ -> Error(Nil)
    }
  })
  |> string.join("")
}

/// Get the accumulated tool inputs so far
pub fn get_accumulated_tool_inputs(
  state: AccumulatorState,
) -> List(#(String, String, String)) {
  state.content_blocks
  |> dict.values
  |> list.filter_map(fn(block) {
    case block {
      ToolUseBlockState(id, name, input) -> Ok(#(id, name, input))
      _ -> Error(Nil)
    }
  })
}

/// Check if accumulator has any content
pub fn has_content(state: AccumulatorState) -> Bool {
  dict.size(state.content_blocks) > 0
}

/// Check if accumulator encountered an error
pub fn has_error(state: AccumulatorState) -> Bool {
  option.is_some(state.error)
}

/// Get total token count
pub fn total_tokens(state: AccumulatorState) -> Int {
  state.input_tokens + state.output_tokens
}

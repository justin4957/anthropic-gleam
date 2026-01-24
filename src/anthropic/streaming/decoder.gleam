//// JSON decoder for streaming events
////
//// This module decodes JSON data from SSE events into typed StreamEvent values.
//// It handles all Anthropic streaming event types including message_start,
//// content_block_start, content_block_delta, content_block_stop,
//// message_delta, message_stop, ping, and error events.

import anthropic/internal/sse.{type SseEvent}
import anthropic/message.{type Role, Assistant, TextBlock, ToolUseBlock}
import anthropic/request.{
  type StopReason, EndTurn, MaxTokens, StopSequence, ToolUse,
}
import anthropic/streaming.{
  type ContentBlockDelta, type MessageDelta, type MessageDeltaUsage,
  type MessageStart, type StreamError, type StreamEvent, ContentBlockDeltaEvent,
  ContentBlockDeltaEventVariant, ContentBlockStart, ContentBlockStartEvent,
  ContentBlockStop, ContentBlockStopEvent, ErrorEvent, InputJsonContentDelta,
  InputJsonDelta, MessageDelta, MessageDeltaEvent, MessageDeltaEventVariant,
  MessageDeltaUsage, MessageStartEvent, MessageStopEvent, PingEvent, StreamError,
  TextContentDelta, TextDelta,
}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// Error Types
// =============================================================================

/// Error that can occur during event decoding
pub type DecodeError {
  /// JSON parsing failed
  JsonParseError(message: String)
  /// Unknown event type
  UnknownEventType(event_type: String)
  /// Missing required field
  MissingField(field: String)
  /// Invalid field value
  InvalidFieldValue(field: String, message: String)
}

// =============================================================================
// Main Decode Function
// =============================================================================

/// Decode an SSE event into a StreamEvent
pub fn decode_event(sse_event: SseEvent) -> Result(StreamEvent, DecodeError) {
  let event_type = sse.get_event_type(sse_event)

  case event_type {
    "ping" -> Ok(PingEvent)
    "message_stop" -> Ok(MessageStopEvent)
    _ -> decode_data_event(event_type, sse.get_data(sse_event))
  }
}

/// Decode an event that has JSON data
fn decode_data_event(
  event_type: String,
  data: String,
) -> Result(StreamEvent, DecodeError) {
  case parse_json(data) {
    Error(_) -> Error(JsonParseError("Failed to parse JSON: " <> data))
    Ok(json) -> decode_typed_event(event_type, json)
  }
}

/// Decode a typed event from parsed JSON
fn decode_typed_event(
  event_type: String,
  json: Dynamic,
) -> Result(StreamEvent, DecodeError) {
  case event_type {
    "message_start" -> decode_message_start(json)
    "content_block_start" -> decode_content_block_start(json)
    "content_block_delta" -> decode_content_block_delta(json)
    "content_block_stop" -> decode_content_block_stop(json)
    "message_delta" -> decode_message_delta(json)
    "error" -> decode_error(json)
    _ -> Error(UnknownEventType(event_type))
  }
}

// =============================================================================
// Event Decoders
// =============================================================================

/// Decode a message_start event
fn decode_message_start(json: Dynamic) -> Result(StreamEvent, DecodeError) {
  let decoder = {
    use message <- decode.field("message", message_start_decoder())
    decode.success(message)
  }

  case decode.run(json, decoder) {
    Ok(msg) -> Ok(MessageStartEvent(message: msg))
    Error(errors) ->
      Error(JsonParseError(
        "Failed to decode message_start: " <> format_errors(errors),
      ))
  }
}

/// Decoder for MessageStart within the message field
fn message_start_decoder() -> decode.Decoder(MessageStart) {
  use id <- decode.field("id", decode.string)
  use message_type <- decode.field("type", decode.string)
  use role_str <- decode.field("role", decode.string)
  use model <- decode.field("model", decode.string)
  use usage <- decode.field("usage", usage_decoder())

  let role = parse_role(role_str)

  decode.success(streaming.MessageStart(
    id: id,
    message_type: message_type,
    role: role,
    model: model,
    usage: usage,
  ))
}

/// Decode a content_block_start event
fn decode_content_block_start(json: Dynamic) -> Result(StreamEvent, DecodeError) {
  let decoder = {
    use index <- decode.field("index", decode.int)
    use content_block <- decode.field(
      "content_block",
      content_block_start_decoder(),
    )
    decode.success(#(index, content_block))
  }

  case decode.run(json, decoder) {
    Ok(#(index, block)) ->
      Ok(
        ContentBlockStartEvent(content_block_start: ContentBlockStart(
          index: index,
          content_block: block,
        )),
      )
    Error(errors) ->
      Error(JsonParseError(
        "Failed to decode content_block_start: " <> format_errors(errors),
      ))
  }
}

/// Decoder for content block in content_block_start
fn content_block_start_decoder() -> decode.Decoder(message.ContentBlock) {
  use block_type <- decode.field("type", decode.string)

  case block_type {
    "text" -> {
      use text <- decode.optional_field("text", "", decode.string)
      decode.success(TextBlock(text: text))
    }
    "tool_use" -> {
      use id <- decode.field("id", decode.string)
      use name <- decode.field("name", decode.string)
      decode.success(ToolUseBlock(id: id, name: name, input: ""))
    }
    _ -> decode.success(TextBlock(text: ""))
  }
}

/// Decode a content_block_delta event
fn decode_content_block_delta(json: Dynamic) -> Result(StreamEvent, DecodeError) {
  let decoder = {
    use index <- decode.field("index", decode.int)
    use delta <- decode.field("delta", delta_decoder())
    decode.success(#(index, delta))
  }

  case decode.run(json, decoder) {
    Ok(#(index, delta)) ->
      Ok(
        ContentBlockDeltaEventVariant(
          content_block_delta: ContentBlockDeltaEvent(
            index: index,
            delta: delta,
          ),
        ),
      )
    Error(errors) ->
      Error(JsonParseError(
        "Failed to decode content_block_delta: " <> format_errors(errors),
      ))
  }
}

/// Decoder for delta content
fn delta_decoder() -> decode.Decoder(ContentBlockDelta) {
  use delta_type <- decode.field("type", decode.string)

  case delta_type {
    "text_delta" -> {
      use text <- decode.field("text", decode.string)
      decode.success(TextContentDelta(TextDelta(text: text)))
    }
    "input_json_delta" -> {
      use partial_json <- decode.field("partial_json", decode.string)
      decode.success(
        InputJsonContentDelta(InputJsonDelta(partial_json: partial_json)),
      )
    }
    _ -> decode.success(TextContentDelta(TextDelta(text: "")))
  }
}

/// Decode a content_block_stop event
fn decode_content_block_stop(json: Dynamic) -> Result(StreamEvent, DecodeError) {
  let decoder = {
    use index <- decode.field("index", decode.int)
    decode.success(index)
  }

  case decode.run(json, decoder) {
    Ok(index) ->
      Ok(
        ContentBlockStopEvent(content_block_stop: ContentBlockStop(index: index)),
      )
    Error(errors) ->
      Error(JsonParseError(
        "Failed to decode content_block_stop: " <> format_errors(errors),
      ))
  }
}

/// Decode a message_delta event
fn decode_message_delta(json: Dynamic) -> Result(StreamEvent, DecodeError) {
  let decoder = {
    use delta <- decode.field("delta", message_delta_inner_decoder())
    use usage <- decode.field("usage", message_delta_usage_decoder())
    decode.success(#(delta, usage))
  }

  case decode.run(json, decoder) {
    Ok(#(delta, usage)) ->
      Ok(
        MessageDeltaEventVariant(message_delta: MessageDeltaEvent(
          delta: delta,
          usage: usage,
        )),
      )
    Error(errors) ->
      Error(JsonParseError(
        "Failed to decode message_delta: " <> format_errors(errors),
      ))
  }
}

/// Decoder for message delta inner content
fn message_delta_inner_decoder() -> decode.Decoder(MessageDelta) {
  use stop_reason <- decode.optional_field(
    "stop_reason",
    None,
    decode.string |> decode.map(fn(s) { parse_stop_reason(s) }),
  )
  use stop_sequence <- decode.optional_field(
    "stop_sequence",
    None,
    decode.string |> decode.map(Some),
  )

  decode.success(MessageDelta(
    stop_reason: stop_reason,
    stop_sequence: stop_sequence,
  ))
}

/// Decoder for message delta usage
fn message_delta_usage_decoder() -> decode.Decoder(MessageDeltaUsage) {
  use output_tokens <- decode.field("output_tokens", decode.int)
  decode.success(MessageDeltaUsage(output_tokens: output_tokens))
}

/// Decode an error event
fn decode_error(json: Dynamic) -> Result(StreamEvent, DecodeError) {
  let decoder = {
    use error <- decode.field("error", error_inner_decoder())
    decode.success(error)
  }

  case decode.run(json, decoder) {
    Ok(error) -> Ok(ErrorEvent(error: error))
    Error(errors) ->
      Error(JsonParseError("Failed to decode error: " <> format_errors(errors)))
  }
}

/// Decoder for error inner content
fn error_inner_decoder() -> decode.Decoder(StreamError) {
  use error_type <- decode.field("type", decode.string)
  use message <- decode.field("message", decode.string)
  decode.success(StreamError(error_type: error_type, message: message))
}

// =============================================================================
// Helper Decoders
// =============================================================================

/// Decoder for Usage
fn usage_decoder() -> decode.Decoder(request.Usage) {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.optional_field("output_tokens", 0, decode.int)
  decode.success(request.Usage(
    input_tokens: input_tokens,
    output_tokens: output_tokens,
  ))
}

// =============================================================================
// Utility Functions
// =============================================================================

/// Parse role from string
fn parse_role(str: String) -> Role {
  case str {
    "assistant" -> Assistant
    _ -> Assistant
  }
}

/// Parse stop reason from string
fn parse_stop_reason(str: String) -> Option(StopReason) {
  case str {
    "end_turn" -> Some(EndTurn)
    "max_tokens" -> Some(MaxTokens)
    "stop_sequence" -> Some(StopSequence)
    "tool_use" -> Some(ToolUse)
    _ -> None
  }
}

/// Format decode errors to string
fn format_errors(errors: List(decode.DecodeError)) -> String {
  errors
  |> list.map(fn(e) { "expected " <> e.expected <> ", got " <> e.found })
  |> string.join("; ")
}

/// Parse JSON string to Dynamic
@external(erlang, "gleam_json_ffi", "decode")
fn parse_json(json: String) -> Result(Dynamic, Nil)

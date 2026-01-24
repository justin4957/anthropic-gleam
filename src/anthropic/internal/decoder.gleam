//// Shared JSON response decoders for Anthropic API
////
//// This module provides common JSON decoders used across the library for
//// parsing API responses. Both the high-level `api.gleam` and the sans-io
//// `http.gleam` modules use these shared decoders.
////
//// ## Internal Module
////
//// This module is primarily for internal use. Most users should use the
//// higher-level functions in `anthropic/api` or `anthropic/http` instead.

import anthropic/error.{type AnthropicError, type ApiErrorType}
import anthropic/message.{
  type ContentBlock, type Role, Assistant, TextBlock, ToolUseBlock, User,
}
import anthropic/request.{
  type CreateMessageResponse, type StopReason, type Usage, EndTurn, MaxTokens,
  StopSequence, ToolUse,
}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// JSON Parsing
// =============================================================================

/// Parse a JSON string to Dynamic
@external(erlang, "gleam_json_ffi", "decode")
pub fn parse_json(json: String) -> Result(Dynamic, Nil)

/// Parse response body JSON and decode into CreateMessageResponse
pub fn parse_response_body(
  body: String,
) -> Result(CreateMessageResponse, AnthropicError) {
  case parse_json(body) {
    Ok(dyn) -> decode_response(dyn)
    Error(_) -> Error(error.json_error("Failed to parse response JSON"))
  }
}

/// Decode a dynamic value into CreateMessageResponse
pub fn decode_response(
  value: Dynamic,
) -> Result(CreateMessageResponse, AnthropicError) {
  let decoder = response_decoder()
  case decode.run(value, decoder) {
    Ok(response) -> Ok(response)
    Error(errors) ->
      Error(error.json_error(
        "Failed to decode response: " <> decode_errors_to_string(errors),
      ))
  }
}

// =============================================================================
// Decoders
// =============================================================================

/// Decoder for CreateMessageResponse
pub fn response_decoder() -> decode.Decoder(CreateMessageResponse) {
  use id <- decode.field("id", decode.string)
  use response_type <- decode.field("type", decode.string)
  use role_str <- decode.field("role", decode.string)
  use content <- decode.field("content", decode.list(content_block_decoder()))
  use model <- decode.field("model", decode.string)
  use usage <- decode.field("usage", usage_decoder())
  use stop_reason <- decode.field(
    "stop_reason",
    decode.optional(decode.string)
      |> decode.map(fn(opt) {
        case opt {
          Some(s) -> parse_stop_reason(s)
          None -> None
        }
      }),
  )
  use stop_sequence <- decode.field(
    "stop_sequence",
    decode.optional(decode.string),
  )

  let role = parse_role(role_str)

  decode.success(request.CreateMessageResponse(
    id: id,
    response_type: response_type,
    role: role,
    content: content,
    model: model,
    stop_reason: stop_reason,
    stop_sequence: stop_sequence,
    usage: usage,
  ))
}

/// Decoder for ContentBlock
pub fn content_block_decoder() -> decode.Decoder(ContentBlock) {
  use block_type <- decode.field("type", decode.string)

  case block_type {
    "text" -> text_block_decoder()
    "tool_use" -> tool_use_block_decoder()
    _ ->
      // Return a placeholder for unknown types
      decode.success(TextBlock(
        text: "[Unknown content type: " <> block_type <> "]",
      ))
  }
}

/// Decoder for text blocks
pub fn text_block_decoder() -> decode.Decoder(ContentBlock) {
  use text <- decode.field("text", decode.string)
  decode.success(TextBlock(text: text))
}

/// Decoder for tool use blocks
pub fn tool_use_block_decoder() -> decode.Decoder(ContentBlock) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use input <- decode.field("input", input_decoder())

  decode.success(ToolUseBlock(id: id, name: name, input: input))
}

/// Decoder for tool input (converts dynamic to JSON string)
pub fn input_decoder() -> decode.Decoder(String) {
  decode.new_primitive_decoder("Object", fn(data) {
    let json_str = dynamic_to_json_string(data)
    Ok(json_str)
  })
}

/// Decoder for Usage
pub fn usage_decoder() -> decode.Decoder(Usage) {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)

  decode.success(request.Usage(
    input_tokens: input_tokens,
    output_tokens: output_tokens,
  ))
}

// =============================================================================
// Parsing Helpers
// =============================================================================

/// Parse a role string to Role type
pub fn parse_role(str: String) -> Role {
  case str {
    "user" -> User
    "assistant" -> Assistant
    _ -> Assistant
  }
}

/// Parse a stop reason string to Option(StopReason)
pub fn parse_stop_reason(str: String) -> Option(StopReason) {
  case str {
    "end_turn" -> Some(EndTurn)
    "max_tokens" -> Some(MaxTokens)
    "stop_sequence" -> Some(StopSequence)
    "tool_use" -> Some(ToolUse)
    _ -> None
  }
}

/// Convert decode errors to a human-readable string
pub fn decode_errors_to_string(errors: List(decode.DecodeError)) -> String {
  errors
  |> list.map(fn(e) { "expected " <> e.expected <> ", got " <> e.found })
  |> string.join("; ")
}

// =============================================================================
// Internal Helpers
// =============================================================================

/// Convert a dynamic value to a JSON string
fn dynamic_to_json_string(value: Dynamic) -> String {
  let iodata = json_encode(value)
  iolist_to_binary(iodata)
}

/// Encode dynamic value to JSON using Erlang's built-in json module (OTP 27+)
@external(erlang, "json", "encode")
fn json_encode(value: Dynamic) -> Dynamic

/// Convert iodata to binary string
@external(erlang, "erlang", "iolist_to_binary")
fn iolist_to_binary(data: Dynamic) -> String

// =============================================================================
// Error Response Parsing
// =============================================================================

/// Parse an API error response body into an AnthropicError
///
/// This function attempts to parse the Anthropic API error format:
/// ```json
/// {
///   "type": "error",
///   "error": {
///     "type": "invalid_request_error",
///     "message": "..."
///   }
/// }
/// ```
///
/// If parsing fails, it falls back to creating an error with the default type
/// and the raw body as the message.
pub fn parse_api_error(
  status_code: Int,
  body: String,
  default_type: ApiErrorType,
) -> AnthropicError {
  case parse_error_body(body) {
    Ok(#(error_type, message, param, code)) ->
      error.api_error(
        status_code,
        error.api_error_details_full(error_type, message, param, code),
      )
    Error(_) ->
      error.api_error(status_code, error.api_error_details(default_type, body))
  }
}

/// Parse error body JSON into error details tuple
///
/// Returns a tuple of (ApiErrorType, message, optional param, optional code)
pub fn parse_error_body(
  body: String,
) -> Result(#(ApiErrorType, String, Option(String), Option(String)), Nil) {
  case parse_json(body) {
    Ok(dyn) ->
      case decode.run(dyn, error_wrapper_decoder()) {
        Ok(details) -> Ok(details)
        Error(_) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

/// Decoder for the error wrapper object
fn error_wrapper_decoder() -> decode.Decoder(
  #(ApiErrorType, String, Option(String), Option(String)),
) {
  use details <- decode.field("error", error_details_decoder())
  decode.success(details)
}

/// Decoder for the inner error details
fn error_details_decoder() -> decode.Decoder(
  #(ApiErrorType, String, Option(String), Option(String)),
) {
  use error_type_str <- decode.field("type", decode.string)
  use message <- decode.field("message", decode.string)
  use param <- decode.optional_field(
    "param",
    None,
    decode.string |> decode.map(Some),
  )
  use code <- decode.optional_field(
    "code",
    None,
    decode.string |> decode.map(Some),
  )

  let error_type = error.api_error_type_from_string(error_type_str)
  decode.success(#(error_type, message, param, code))
}

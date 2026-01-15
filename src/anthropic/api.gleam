//// API functions for Anthropic Messages API
////
//// This module provides the core functions for interacting with Claude's
//// Messages API, including message creation and response parsing.

import anthropic/client.{type Client, messages_endpoint}
import anthropic/types/error.{type AnthropicError}
import anthropic/types/message.{
  type ContentBlock, type Role, Assistant, TextBlock, ToolUseBlock, User,
}
import anthropic/types/request.{
  type CreateMessageRequest, type CreateMessageResponse, type StopReason,
  type Usage, EndTurn, MaxTokens, StopSequence, ToolUse,
}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// =============================================================================
// Message Creation
// =============================================================================

/// Create a message using the Anthropic Messages API
///
/// This function sends a request to Claude and returns the response.
///
/// ## Example
///
/// ```gleam
/// let request = create_request(
///   "claude-sonnet-4-20250514",
///   [user_message("Hello, Claude!")],
///   1024,
/// )
/// case create_message(client, request) {
///   Ok(response) -> io.println(response_text(response))
///   Error(err) -> io.println(error_to_string(err))
/// }
/// ```
pub fn create_message(
  client: Client,
  request: CreateMessageRequest,
) -> Result(CreateMessageResponse, AnthropicError) {
  // Validate the request
  use _ <- result.try(validate_request(request))

  // Encode request to JSON
  let body = request.request_to_json_string(request)

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
// Request Validation
// =============================================================================

/// Validate a CreateMessageRequest before sending
fn validate_request(
  request: CreateMessageRequest,
) -> Result(Nil, AnthropicError) {
  // Check for empty messages
  case list.is_empty(request.messages) {
    True -> Error(error.invalid_request_error("messages list cannot be empty"))
    False -> Ok(Nil)
  }
  |> result.try(fn(_) {
    // Check for valid model name
    case string.is_empty(string.trim(request.model)) {
      True -> Error(error.invalid_request_error("model name cannot be empty"))
      False -> Ok(Nil)
    }
  })
  |> result.try(fn(_) {
    // Check for positive max_tokens
    case request.max_tokens > 0 {
      True -> Ok(Nil)
      False ->
        Error(error.invalid_request_error("max_tokens must be greater than 0"))
    }
  })
}

// =============================================================================
// Response Parsing
// =============================================================================

/// Parse a response body into CreateMessageResponse
fn parse_response(body: String) -> Result(CreateMessageResponse, AnthropicError) {
  case parse_json_to_dynamic(body) {
    Ok(dyn) -> decode_response(dyn)
    Error(_) -> Error(error.json_error("Failed to parse response JSON"))
  }
}

/// Parse a JSON string to Dynamic
@external(erlang, "gleam_json_ffi", "decode")
fn parse_json_to_dynamic(json: String) -> Result(Dynamic, Nil)

/// Decode a dynamic value into CreateMessageResponse
fn decode_response(
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

/// Convert decode errors to a string
fn decode_errors_to_string(errors: List(decode.DecodeError)) -> String {
  errors
  |> list.map(fn(e) { "expected " <> e.expected <> ", got " <> e.found })
  |> string.join("; ")
}

/// Decoder for CreateMessageResponse
fn response_decoder() -> decode.Decoder(CreateMessageResponse) {
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
fn content_block_decoder() -> decode.Decoder(ContentBlock) {
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
fn text_block_decoder() -> decode.Decoder(ContentBlock) {
  use text <- decode.field("text", decode.string)
  decode.success(TextBlock(text: text))
}

/// Decoder for tool use blocks
fn tool_use_block_decoder() -> decode.Decoder(ContentBlock) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  // Input is stored as a JSON string - we'll convert the dynamic to string
  use input <- decode.field("input", input_decoder())

  decode.success(ToolUseBlock(id: id, name: name, input: input))
}

/// Decoder for tool input (converts dynamic to JSON string)
fn input_decoder() -> decode.Decoder(String) {
  decode.new_primitive_decoder("Object", fn(data) {
    // Convert the dynamic value to a JSON string representation
    let json_str = dynamic_to_json_string(data)
    Ok(json_str)
  })
}

/// Convert a dynamic value to a JSON string using Erlang's built-in json module
fn dynamic_to_json_string(value: Dynamic) -> String {
  // Use Erlang's built-in json:encode which returns iodata
  let iodata = json_encode(value)
  iolist_to_binary(iodata)
}

/// Encode dynamic value to JSON using Erlang's built-in json module (OTP 27+)
@external(erlang, "json", "encode")
fn json_encode(value: Dynamic) -> Dynamic

/// Convert iodata to binary string
@external(erlang, "erlang", "iolist_to_binary")
fn iolist_to_binary(data: Dynamic) -> String

/// Decoder for Usage
fn usage_decoder() -> decode.Decoder(Usage) {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)

  decode.success(request.Usage(
    input_tokens: input_tokens,
    output_tokens: output_tokens,
  ))
}

/// Parse a role string
fn parse_role(str: String) -> Role {
  case str {
    "user" -> User
    "assistant" -> Assistant
    _ -> Assistant
  }
}

/// Parse a stop reason string
fn parse_stop_reason(str: String) -> Option(StopReason) {
  case str {
    "end_turn" -> Some(EndTurn)
    "max_tokens" -> Some(MaxTokens)
    "stop_sequence" -> Some(StopSequence)
    "tool_use" -> Some(ToolUse)
    _ -> None
  }
}

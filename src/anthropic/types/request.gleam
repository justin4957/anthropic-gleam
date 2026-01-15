//// API request and response types for the Anthropic Messages API
////
//// This module defines the types for creating message requests and
//// parsing message responses from Claude's API.

import anthropic/types/message.{
  type ContentBlock, type Message, type Role, Assistant, TextBlock, ToolUseBlock,
  messages_to_json,
}
import anthropic/types/tool.{
  type Tool, type ToolChoice, tool_choice_to_json, tools_to_json,
}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// StopReason
// =============================================================================

/// Reason why the model stopped generating
pub type StopReason {
  /// Model reached a natural stopping point
  EndTurn
  /// Model reached the max_tokens limit
  MaxTokens
  /// Model encountered a stop sequence
  StopSequence
  /// Model is requesting to use a tool
  ToolUse
}

/// Convert a StopReason to its JSON string representation
pub fn stop_reason_to_string(reason: StopReason) -> String {
  case reason {
    EndTurn -> "end_turn"
    MaxTokens -> "max_tokens"
    StopSequence -> "stop_sequence"
    ToolUse -> "tool_use"
  }
}

/// Encode a StopReason to JSON
pub fn stop_reason_to_json(reason: StopReason) -> Json {
  json.string(stop_reason_to_string(reason))
}

/// Parse a string into a StopReason
pub fn stop_reason_from_string(str: String) -> Result(StopReason, String) {
  case str {
    "end_turn" -> Ok(EndTurn)
    "max_tokens" -> Ok(MaxTokens)
    "stop_sequence" -> Ok(StopSequence)
    "tool_use" -> Ok(ToolUse)
    _ -> Error("Invalid stop reason: " <> str)
  }
}

// =============================================================================
// Usage
// =============================================================================

/// Token usage information from an API response
pub type Usage {
  Usage(
    /// Number of tokens in the input/prompt
    input_tokens: Int,
    /// Number of tokens in the output/completion
    output_tokens: Int,
  )
}

/// Create a Usage from input and output token counts
pub fn usage(input_tokens: Int, output_tokens: Int) -> Usage {
  Usage(input_tokens: input_tokens, output_tokens: output_tokens)
}

/// Encode Usage to JSON
pub fn usage_to_json(u: Usage) -> Json {
  json.object([
    #("input_tokens", json.int(u.input_tokens)),
    #("output_tokens", json.int(u.output_tokens)),
  ])
}

// =============================================================================
// Metadata
// =============================================================================

/// Optional metadata for requests
pub type Metadata {
  Metadata(
    /// External identifier for the user making the request
    user_id: Option(String),
  )
}

/// Encode Metadata to JSON
pub fn metadata_to_json(metadata: Metadata) -> Json {
  case metadata.user_id {
    Some(user_id) -> json.object([#("user_id", json.string(user_id))])
    None -> json.object([])
  }
}

// =============================================================================
// CreateMessageRequest
// =============================================================================

/// Request to create a message via the Messages API
pub type CreateMessageRequest {
  CreateMessageRequest(
    /// The model to use (e.g., "claude-opus-4-20250514", "claude-sonnet-4-20250514")
    model: String,
    /// List of messages in the conversation
    messages: List(Message),
    /// Maximum number of tokens to generate
    max_tokens: Int,
    /// System prompt to set context for the conversation
    system: Option(String),
    /// Temperature for sampling (0.0 to 1.0)
    temperature: Option(Float),
    /// Top-p sampling parameter
    top_p: Option(Float),
    /// Top-k sampling parameter
    top_k: Option(Int),
    /// Sequences that will stop generation
    stop_sequences: Option(List(String)),
    /// Whether to stream the response
    stream: Option(Bool),
    /// Optional metadata including user_id
    metadata: Option(Metadata),
    /// List of tools available to the model
    tools: Option(List(Tool)),
    /// How the model should choose which tool to use
    tool_choice: Option(ToolChoice),
  )
}

/// Create a basic request with required fields only
pub fn create_request(
  model: String,
  messages: List(Message),
  max_tokens: Int,
) -> CreateMessageRequest {
  CreateMessageRequest(
    model: model,
    messages: messages,
    max_tokens: max_tokens,
    system: None,
    temperature: None,
    top_p: None,
    top_k: None,
    stop_sequences: None,
    stream: None,
    metadata: None,
    tools: None,
    tool_choice: None,
  )
}

/// Set the system prompt on a request
pub fn with_system(
  request: CreateMessageRequest,
  system: String,
) -> CreateMessageRequest {
  CreateMessageRequest(..request, system: Some(system))
}

/// Set the temperature on a request
pub fn with_temperature(
  request: CreateMessageRequest,
  temperature: Float,
) -> CreateMessageRequest {
  CreateMessageRequest(..request, temperature: Some(temperature))
}

/// Set top_p on a request
pub fn with_top_p(
  request: CreateMessageRequest,
  top_p: Float,
) -> CreateMessageRequest {
  CreateMessageRequest(..request, top_p: Some(top_p))
}

/// Set top_k on a request
pub fn with_top_k(
  request: CreateMessageRequest,
  top_k: Int,
) -> CreateMessageRequest {
  CreateMessageRequest(..request, top_k: Some(top_k))
}

/// Set stop sequences on a request
pub fn with_stop_sequences(
  request: CreateMessageRequest,
  sequences: List(String),
) -> CreateMessageRequest {
  CreateMessageRequest(..request, stop_sequences: Some(sequences))
}

/// Enable streaming on a request
pub fn with_stream(
  request: CreateMessageRequest,
  stream: Bool,
) -> CreateMessageRequest {
  CreateMessageRequest(..request, stream: Some(stream))
}

/// Set metadata on a request
pub fn with_metadata(
  request: CreateMessageRequest,
  metadata: Metadata,
) -> CreateMessageRequest {
  CreateMessageRequest(..request, metadata: Some(metadata))
}

/// Set user_id in metadata on a request
pub fn with_user_id(
  request: CreateMessageRequest,
  user_id: String,
) -> CreateMessageRequest {
  CreateMessageRequest(
    ..request,
    metadata: Some(Metadata(user_id: Some(user_id))),
  )
}

/// Set tools on a request
pub fn with_tools(
  request: CreateMessageRequest,
  tools: List(Tool),
) -> CreateMessageRequest {
  CreateMessageRequest(..request, tools: Some(tools))
}

/// Set tool choice on a request
pub fn with_tool_choice(
  request: CreateMessageRequest,
  choice: ToolChoice,
) -> CreateMessageRequest {
  CreateMessageRequest(..request, tool_choice: Some(choice))
}

/// Set tools and tool choice on a request (convenience function)
pub fn with_tools_and_choice(
  request: CreateMessageRequest,
  tools: List(Tool),
  choice: ToolChoice,
) -> CreateMessageRequest {
  CreateMessageRequest(..request, tools: Some(tools), tool_choice: Some(choice))
}

/// Encode a CreateMessageRequest to JSON
pub fn request_to_json(request: CreateMessageRequest) -> Json {
  let required_fields = [
    #("model", json.string(request.model)),
    #("messages", messages_to_json(request.messages)),
    #("max_tokens", json.int(request.max_tokens)),
  ]

  let optional_fields =
    []
    |> add_optional_string("system", request.system)
    |> add_optional_float("temperature", request.temperature)
    |> add_optional_float("top_p", request.top_p)
    |> add_optional_int("top_k", request.top_k)
    |> add_optional_string_list("stop_sequences", request.stop_sequences)
    |> add_optional_bool("stream", request.stream)
    |> add_optional_metadata("metadata", request.metadata)
    |> add_optional_tools("tools", request.tools)
    |> add_optional_tool_choice("tool_choice", request.tool_choice)

  json.object(list.append(required_fields, optional_fields))
}

/// Convert a request to a JSON string
pub fn request_to_json_string(request: CreateMessageRequest) -> String {
  request
  |> request_to_json
  |> json.to_string
}

// Helper functions for building JSON with optional fields
fn add_optional_string(
  fields: List(#(String, Json)),
  key: String,
  value: Option(String),
) -> List(#(String, Json)) {
  case value {
    Some(v) -> list.append(fields, [#(key, json.string(v))])
    None -> fields
  }
}

fn add_optional_float(
  fields: List(#(String, Json)),
  key: String,
  value: Option(Float),
) -> List(#(String, Json)) {
  case value {
    Some(v) -> list.append(fields, [#(key, json.float(v))])
    None -> fields
  }
}

fn add_optional_int(
  fields: List(#(String, Json)),
  key: String,
  value: Option(Int),
) -> List(#(String, Json)) {
  case value {
    Some(v) -> list.append(fields, [#(key, json.int(v))])
    None -> fields
  }
}

fn add_optional_bool(
  fields: List(#(String, Json)),
  key: String,
  value: Option(Bool),
) -> List(#(String, Json)) {
  case value {
    Some(v) -> list.append(fields, [#(key, json.bool(v))])
    None -> fields
  }
}

fn add_optional_string_list(
  fields: List(#(String, Json)),
  key: String,
  value: Option(List(String)),
) -> List(#(String, Json)) {
  case value {
    Some(v) -> list.append(fields, [#(key, json.array(v, json.string))])
    None -> fields
  }
}

fn add_optional_metadata(
  fields: List(#(String, Json)),
  key: String,
  value: Option(Metadata),
) -> List(#(String, Json)) {
  case value {
    Some(m) -> list.append(fields, [#(key, metadata_to_json(m))])
    None -> fields
  }
}

fn add_optional_tools(
  fields: List(#(String, Json)),
  key: String,
  value: Option(List(Tool)),
) -> List(#(String, Json)) {
  case value {
    Some(t) -> list.append(fields, [#(key, tools_to_json(t))])
    None -> fields
  }
}

fn add_optional_tool_choice(
  fields: List(#(String, Json)),
  key: String,
  value: Option(ToolChoice),
) -> List(#(String, Json)) {
  case value {
    Some(tc) -> list.append(fields, [#(key, tool_choice_to_json(tc))])
    None -> fields
  }
}

// =============================================================================
// CreateMessageResponse
// =============================================================================

/// Response from the Messages API
pub type CreateMessageResponse {
  CreateMessageResponse(
    /// Unique identifier for this message
    id: String,
    /// Object type, always "message"
    response_type: String,
    /// Role of the response, always "assistant"
    role: Role,
    /// Content blocks in the response
    content: List(ContentBlock),
    /// Model that generated the response
    model: String,
    /// Reason generation stopped
    stop_reason: Option(StopReason),
    /// The stop sequence that triggered stop_reason, if applicable
    stop_sequence: Option(String),
    /// Token usage information
    usage: Usage,
  )
}

/// Create a response (primarily for testing)
pub fn create_response(
  id: String,
  content: List(ContentBlock),
  model: String,
  stop_reason: Option(StopReason),
  u: Usage,
) -> CreateMessageResponse {
  CreateMessageResponse(
    id: id,
    response_type: "message",
    role: Assistant,
    content: content,
    model: model,
    stop_reason: stop_reason,
    stop_sequence: None,
    usage: u,
  )
}

/// Create a response with a stop sequence
pub fn create_response_with_stop_sequence(
  id: String,
  content: List(ContentBlock),
  model: String,
  stop_reason: StopReason,
  stop_sequence: String,
  u: Usage,
) -> CreateMessageResponse {
  CreateMessageResponse(
    id: id,
    response_type: "message",
    role: Assistant,
    content: content,
    model: model,
    stop_reason: Some(stop_reason),
    stop_sequence: Some(stop_sequence),
    usage: u,
  )
}

/// Get the text content from a response (concatenated)
pub fn response_text(response: CreateMessageResponse) -> String {
  response.content
  |> list.filter_map(fn(block) {
    case block {
      TextBlock(text: text) -> Ok(text)
      _ -> Error(Nil)
    }
  })
  |> string.join("")
}

/// Check if a response contains tool use blocks
pub fn response_has_tool_use(response: CreateMessageResponse) -> Bool {
  list.any(response.content, fn(block) {
    case block {
      ToolUseBlock(_, _, _) -> True
      _ -> False
    }
  })
}

/// Get all tool use blocks from a response
pub fn response_get_tool_uses(
  response: CreateMessageResponse,
) -> List(ContentBlock) {
  list.filter(response.content, fn(block) {
    case block {
      ToolUseBlock(_, _, _) -> True
      _ -> False
    }
  })
}

/// Encode a response to JSON (for testing/serialization)
pub fn response_to_json(response: CreateMessageResponse) -> Json {
  let base_fields = [
    #("id", json.string(response.id)),
    #("type", json.string(response.response_type)),
    #("role", json.string(message.role_to_string(response.role))),
    #("content", json.array(response.content, message.content_block_to_json)),
    #("model", json.string(response.model)),
    #("usage", usage_to_json(response.usage)),
  ]

  let with_stop_reason = case response.stop_reason {
    Some(reason) ->
      list.append(base_fields, [
        #("stop_reason", stop_reason_to_json(reason)),
      ])
    None -> base_fields
  }

  let with_stop_sequence = case response.stop_sequence {
    Some(seq) ->
      list.append(with_stop_reason, [#("stop_sequence", json.string(seq))])
    None -> with_stop_reason
  }

  json.object(with_stop_sequence)
}

/// Convert a response to a JSON string
pub fn response_to_json_string(response: CreateMessageResponse) -> String {
  response
  |> response_to_json
  |> json.to_string
}

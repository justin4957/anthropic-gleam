//// API request and response types for the Anthropic Messages API
////
//// This module defines the types for creating message requests and
//// parsing message responses from Claude's API.

import anthropic/message.{
  type ContentBlock, type Message, type Role, Assistant, TextBlock, ToolUseBlock,
  messages_to_json,
}
import anthropic/tool.{
  type Tool, type ToolCall, type ToolChoice, ToolCall, tool_choice_to_json,
  tools_to_json,
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
// RequestOptions - For bulk option setting
// =============================================================================

/// Options for configuring a message request
///
/// Use this when you want to specify multiple options at once, or when
/// copying options between requests. For simple cases, the builder pattern
/// with `with_*` functions is recommended.
///
/// ## Example
///
/// ```gleam
/// // Create reusable options
/// let opts = request.options()
///   |> request.opt_system("You are a helpful assistant")
///   |> request.opt_temperature(0.7)
///   |> request.opt_max_tokens(2048)
///
/// // Use options with new_with
/// let req = request.new_with("claude-sonnet-4-20250514", messages, opts)
/// ```
pub type RequestOptions {
  RequestOptions(
    /// Maximum number of tokens to generate (required, defaults to 1024)
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

/// Create default request options
///
/// Returns options with max_tokens set to 1024 and all other options as None.
///
/// ## Example
///
/// ```gleam
/// let opts = request.options()
///   |> request.opt_temperature(0.8)
///   |> request.opt_system("Be concise")
/// ```
pub fn options() -> RequestOptions {
  RequestOptions(
    max_tokens: 1024,
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

/// Set max_tokens in options
pub fn opt_max_tokens(opts: RequestOptions, max_tokens: Int) -> RequestOptions {
  RequestOptions(..opts, max_tokens: max_tokens)
}

/// Set system prompt in options
pub fn opt_system(opts: RequestOptions, system: String) -> RequestOptions {
  RequestOptions(..opts, system: Some(system))
}

/// Set temperature in options
pub fn opt_temperature(
  opts: RequestOptions,
  temperature: Float,
) -> RequestOptions {
  RequestOptions(..opts, temperature: Some(temperature))
}

/// Set top_p in options
pub fn opt_top_p(opts: RequestOptions, top_p: Float) -> RequestOptions {
  RequestOptions(..opts, top_p: Some(top_p))
}

/// Set top_k in options
pub fn opt_top_k(opts: RequestOptions, top_k: Int) -> RequestOptions {
  RequestOptions(..opts, top_k: Some(top_k))
}

/// Set stop sequences in options
pub fn opt_stop_sequences(
  opts: RequestOptions,
  sequences: List(String),
) -> RequestOptions {
  RequestOptions(..opts, stop_sequences: Some(sequences))
}

/// Set stream in options
pub fn opt_stream(opts: RequestOptions, stream: Bool) -> RequestOptions {
  RequestOptions(..opts, stream: Some(stream))
}

/// Set metadata in options
pub fn opt_metadata(opts: RequestOptions, metadata: Metadata) -> RequestOptions {
  RequestOptions(..opts, metadata: Some(metadata))
}

/// Set user_id in options (creates Metadata automatically)
pub fn opt_user_id(opts: RequestOptions, user_id: String) -> RequestOptions {
  RequestOptions(..opts, metadata: Some(Metadata(user_id: Some(user_id))))
}

/// Set tools in options
pub fn opt_tools(opts: RequestOptions, tools: List(Tool)) -> RequestOptions {
  RequestOptions(..opts, tools: Some(tools))
}

/// Set tool choice in options
pub fn opt_tool_choice(
  opts: RequestOptions,
  choice: ToolChoice,
) -> RequestOptions {
  RequestOptions(..opts, tool_choice: Some(choice))
}

/// Set tools and tool choice in options (convenience function)
pub fn opt_tools_and_choice(
  opts: RequestOptions,
  tools: List(Tool),
  choice: ToolChoice,
) -> RequestOptions {
  RequestOptions(..opts, tools: Some(tools), tool_choice: Some(choice))
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

/// Create a new message request with required fields only
///
/// This is the idiomatic Gleam constructor for CreateMessageRequest.
///
/// ## Example
///
/// ```gleam
/// import anthropic/types/request
/// import anthropic/types/message.{user_message}
///
/// let req = request.new(
///   "claude-sonnet-4-20250514",
///   [user_message("Hello, Claude!")],
///   1024,
/// )
/// ```
pub fn new(
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

/// Create a new message request with options
///
/// This allows specifying multiple options at once using a RequestOptions record.
/// Useful for config-driven scenarios, copying options between requests, or
/// when you have many options to set.
///
/// ## Example
///
/// ```gleam
/// import anthropic/types/request
/// import anthropic/types/message.{user_message}
///
/// // Create reusable options
/// let creative_opts = request.options()
///   |> request.opt_system("You are a creative writer")
///   |> request.opt_temperature(0.9)
///   |> request.opt_max_tokens(2048)
///
/// // Use options with new_with
/// let req = request.new_with(
///   "claude-sonnet-4-20250514",
///   [user_message("Write a poem about stars")],
///   creative_opts,
/// )
///
/// // Reuse the same options for another request
/// let req2 = request.new_with(
///   "claude-sonnet-4-20250514",
///   [user_message("Write a poem about the ocean")],
///   creative_opts,
/// )
/// ```
pub fn new_with(
  model: String,
  messages: List(Message),
  opts: RequestOptions,
) -> CreateMessageRequest {
  CreateMessageRequest(
    model: model,
    messages: messages,
    max_tokens: opts.max_tokens,
    system: opts.system,
    temperature: opts.temperature,
    top_p: opts.top_p,
    top_k: opts.top_k,
    stop_sequences: opts.stop_sequences,
    stream: opts.stream,
    metadata: opts.metadata,
    tools: opts.tools,
    tool_choice: opts.tool_choice,
  )
}

/// Extract options from an existing request
///
/// This allows copying options from one request to use in another.
///
/// ## Example
///
/// ```gleam
/// // Extract options from an existing request
/// let opts = request.get_options(existing_request)
///
/// // Modify and use for a new request
/// let new_opts = opts |> request.opt_temperature(0.5)
/// let new_req = request.new_with("claude-sonnet-4-20250514", messages, new_opts)
/// ```
pub fn get_options(req: CreateMessageRequest) -> RequestOptions {
  RequestOptions(
    max_tokens: req.max_tokens,
    system: req.system,
    temperature: req.temperature,
    top_p: req.top_p,
    top_k: req.top_k,
    stop_sequences: req.stop_sequences,
    stream: req.stream,
    metadata: req.metadata,
    tools: req.tools,
    tool_choice: req.tool_choice,
  )
}

/// Apply options to an existing request
///
/// This merges options into an existing request, overwriting any options
/// that are set (not None) in the provided RequestOptions.
///
/// ## Example
///
/// ```gleam
/// let req = request.new("claude-sonnet-4-20250514", messages, 1024)
/// let opts = request.options()
///   |> request.opt_temperature(0.7)
///   |> request.opt_system("Be helpful")
///
/// let updated_req = request.apply_options(req, opts)
/// ```
pub fn apply_options(
  req: CreateMessageRequest,
  opts: RequestOptions,
) -> CreateMessageRequest {
  CreateMessageRequest(
    model: req.model,
    messages: req.messages,
    max_tokens: opts.max_tokens,
    system: merge_option(req.system, opts.system),
    temperature: merge_option(req.temperature, opts.temperature),
    top_p: merge_option(req.top_p, opts.top_p),
    top_k: merge_option(req.top_k, opts.top_k),
    stop_sequences: merge_option(req.stop_sequences, opts.stop_sequences),
    stream: merge_option(req.stream, opts.stream),
    metadata: merge_option(req.metadata, opts.metadata),
    tools: merge_option(req.tools, opts.tools),
    tool_choice: merge_option(req.tool_choice, opts.tool_choice),
  )
}

/// Helper to merge options - new value takes precedence if Some
fn merge_option(existing: Option(a), new: Option(a)) -> Option(a) {
  case new {
    Some(_) -> new
    None -> existing
  }
}

/// Create a basic request with required fields only
///
/// @deprecated Use `request.new` instead for idiomatic Gleam style
@deprecated("Use request.new instead")
pub fn create_request(
  model: String,
  messages: List(Message),
  max_tokens: Int,
) -> CreateMessageRequest {
  new(model, messages, max_tokens)
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

// =============================================================================
// Tool Execution Helpers
// =============================================================================

/// Check if response requires tool execution to continue
///
/// Returns True if the model stopped because it wants to use a tool.
/// This is the signal to extract tool calls, execute them, and continue
/// the conversation with tool results.
///
/// ## Example
///
/// ```gleam
/// case request.needs_tool_execution(response) {
///   True -> {
///     let calls = request.get_pending_tool_calls(response)
///     // Execute tools and continue conversation
///   }
///   False -> {
///     // Response is complete, get the text
///     request.response_text(response)
///   }
/// }
/// ```
pub fn needs_tool_execution(response: CreateMessageResponse) -> Bool {
  case response.stop_reason {
    Some(ToolUse) -> True
    _ -> False
  }
}

/// Extract tool calls that need execution from a response
///
/// Returns a list of structured `ToolCall` records ready for execution.
/// Each `ToolCall` contains the id, name, and input (as JSON string).
///
/// ## Example
///
/// ```gleam
/// let calls = request.get_pending_tool_calls(response)
/// let results = list.map(calls, fn(call) {
///   case call.name {
///     "get_weather" -> execute_weather(call)
///     "search" -> execute_search(call)
///     _ -> ToolFailure(call.id, "Unknown tool")
///   }
/// })
/// ```
pub fn get_pending_tool_calls(response: CreateMessageResponse) -> List(ToolCall) {
  response.content
  |> list.filter_map(fn(block) {
    case block {
      ToolUseBlock(id: id, name: name, input: input) ->
        Ok(ToolCall(id: id, name: name, input: input))
      _ -> Error(Nil)
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

import anthropic/config.{
  api_key_to_string, config_options, default_base_url, default_max_retries,
  default_timeout_ms, load_config, with_api_key, with_base_url,
  with_default_model, with_max_retries, with_timeout_ms,
}
import anthropic/hooks.{
  ContentBlockDelta, ContentBlockStart, ContentBlockStop, MessageDelta,
  MessageStart, MessageStop, RequestEndEvent, RequestStartEvent, RetryEvent,
  StreamClosed, StreamError, StreamEvent, StreamOpened, combine_hooks,
  default_hooks, emit_request_end, emit_request_start, emit_retry,
  emit_stream_event, generate_request_id, has_hooks, metrics_hooks, no_hooks,
  simple_logging_hooks, summarize_request, with_on_request_end,
  with_on_request_start, with_on_retry, with_on_stream_event,
}
import anthropic/hooks as hooks_module
import anthropic/retry.{
  RetryConfig, aggressive_retry_config, calculate_delay, default_retry_config,
  no_retry_config, with_backoff_multiplier, with_base_delay_ms,
  with_jitter_factor, with_max_delay_ms,
}
import anthropic/retry as retry_module
import anthropic/types/error.{
  ApiError, AuthenticationError, ConfigError, HttpError, InternalApiError,
  InvalidRequestError, JsonError, NetworkError, NotFoundError, OverloadedError,
  PermissionError, RateLimitError, TimeoutError, UnknownApiError,
  api_error_details, api_error_details_full, api_error_details_to_json,
  api_error_details_to_string, api_error_type_from_string,
  api_error_type_to_string, authentication_error, config_error, error_category,
  error_to_json, error_to_json_string, error_to_string, get_status_code,
  http_error, internal_api_error, invalid_api_key_error, invalid_request_error,
  is_authentication_error, is_overloaded_error, is_rate_limit_error,
  is_retryable, json_error, missing_api_key_error, network_error,
  overloaded_error, rate_limit_error, timeout_error,
}
import anthropic/types/message.{
  Assistant, Base64, ImageBlock, ImageSource, Message, TextBlock,
  ToolResultBlock, ToolUseBlock, User, assistant_message, content_block_to_json,
  content_block_to_json_string, content_block_type, get_tool_uses, has_tool_use,
  image_source_to_json, message_text, message_to_json, message_to_json_string,
  messages_to_json, role_from_string, role_to_json, role_to_string, user_message,
}
import anthropic/types/request.{
  EndTurn, MaxTokens, Metadata, StopSequence, ToolUse, Usage, apply_options,
  create_request, create_response, create_response_with_stop_sequence,
  get_options, metadata_to_json, new as request_new, new_with, opt_max_tokens,
  opt_metadata, opt_stop_sequences, opt_stream, opt_system, opt_temperature,
  opt_tool_choice, opt_tools, opt_tools_and_choice, opt_top_k, opt_top_p,
  opt_user_id, options, request_to_json, request_to_json_string,
  response_get_tool_uses, response_has_tool_use, response_text, response_to_json,
  response_to_json_string, stop_reason_from_string, stop_reason_to_json,
  stop_reason_to_string, usage_to_json, with_metadata, with_stop_sequences,
  with_stream, with_system, with_temperature, with_tool_choice, with_tools,
  with_tools_and_choice, with_top_k, with_top_p, with_user_id,
}
import anthropic/types/tool.{
  type ToolCall, Any, Auto, EmptyToolName, NoTool, SpecificTool, Tool, ToolCall,
  ToolFailure, ToolSuccess, array_property, empty_input_schema, enum_property,
  input_schema, input_schema_to_json, object_property, property,
  property_schema_to_json, property_with_description, tool_choice_to_json,
  tool_name_to_string, tool_name_unchecked, tool_to_json, tool_to_json_string,
  tools_to_json,
}
import anthropic/validation.{
  MaxTokensField, MessagesField, ModelField, StopSequencesField, SystemField,
  TemperatureField, ToolsField, TopKField, TopPField, errors_to_string,
  field_to_string, get_model_limits, is_valid, validate_content_blocks,
  validate_max_tokens, validate_messages, validate_model, validate_or_error,
  validate_request, validate_stop_sequences, validate_system,
  validate_temperature, validate_tools, validate_top_k, validate_top_p,
  validation_error, validation_error_with_value,
}
import anthropic/validation as validation_module
import gleam/erlang/charlist
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

// =============================================================================
// Role Tests
// =============================================================================

pub fn role_to_json_user_test() {
  let result = role_to_json(User) |> json.to_string
  assert result == "\"user\""
}

pub fn role_to_json_assistant_test() {
  let result = role_to_json(Assistant) |> json.to_string
  assert result == "\"assistant\""
}

pub fn role_from_string_user_test() {
  let result = role_from_string("user")
  assert result == Ok(User)
}

pub fn role_from_string_assistant_test() {
  let result = role_from_string("assistant")
  assert result == Ok(Assistant)
}

pub fn role_from_string_invalid_test() {
  let result = role_from_string("invalid")
  assert result == Error("Invalid role: invalid")
}

pub fn role_to_string_user_test() {
  let result = role_to_string(User)
  assert result == "user"
}

pub fn role_to_string_assistant_test() {
  let result = role_to_string(Assistant)
  assert result == "assistant"
}

// =============================================================================
// ContentBlock Tests
// =============================================================================

pub fn text_block_to_json_test() {
  let block = TextBlock(text: "Hello, world!")
  let result = content_block_to_json(block) |> json.to_string

  assert string.contains(result, "\"type\":\"text\"")
  assert string.contains(result, "\"text\":\"Hello, world!\"")
}

pub fn image_block_to_json_test() {
  let source =
    ImageSource(source_type: Base64, media_type: "image/png", data: "abc123")
  let block = ImageBlock(source: source)
  let result = content_block_to_json(block) |> json.to_string

  assert string.contains(result, "\"type\":\"image\"")
  assert string.contains(result, "\"media_type\":\"image/png\"")
  assert string.contains(result, "\"data\":\"abc123\"")
}

pub fn tool_use_block_to_json_test() {
  let block =
    ToolUseBlock(
      id: "tool_123",
      name: "get_weather",
      input: "{\"city\":\"NYC\"}",
    )
  let result = content_block_to_json(block) |> json.to_string

  assert string.contains(result, "\"type\":\"tool_use\"")
  assert string.contains(result, "\"id\":\"tool_123\"")
  assert string.contains(result, "\"name\":\"get_weather\"")
}

pub fn tool_result_block_to_json_test() {
  let block =
    ToolResultBlock(tool_use_id: "tool_123", content: "72°F", is_error: None)
  let result = content_block_to_json(block) |> json.to_string

  assert string.contains(result, "\"type\":\"tool_result\"")
  assert string.contains(result, "\"tool_use_id\":\"tool_123\"")
  assert string.contains(result, "\"content\":\"72°F\"")
  // Should not contain is_error when None
  assert !string.contains(result, "is_error")
}

pub fn tool_result_block_with_error_to_json_test() {
  let block =
    ToolResultBlock(
      tool_use_id: "tool_123",
      content: "Failed to fetch",
      is_error: Some(True),
    )
  let result = content_block_to_json(block) |> json.to_string

  assert string.contains(result, "\"is_error\":true")
}

pub fn content_block_type_test() {
  assert content_block_type(TextBlock(text: "hi")) == "text"
  assert content_block_type(
      ImageBlock(source: ImageSource(
        source_type: Base64,
        media_type: "image/png",
        data: "",
      )),
    )
    == "image"
  assert content_block_type(ToolUseBlock(id: "", name: "", input: ""))
    == "tool_use"
  assert content_block_type(ToolResultBlock(
      tool_use_id: "",
      content: "",
      is_error: None,
    ))
    == "tool_result"
}

// =============================================================================
// ImageSource Tests
// =============================================================================

pub fn image_source_to_json_test() {
  let source =
    ImageSource(
      source_type: Base64,
      media_type: "image/jpeg",
      data: "base64encodeddata",
    )
  let result = image_source_to_json(source) |> json.to_string

  assert string.contains(result, "\"type\":\"base64\"")
  assert string.contains(result, "\"media_type\":\"image/jpeg\"")
  assert string.contains(result, "\"data\":\"base64encodeddata\"")
}

// =============================================================================
// Message Tests
// =============================================================================

pub fn message_to_json_test() {
  let msg = Message(role: User, content: [TextBlock(text: "Hello!")])
  let result = message_to_json(msg) |> json.to_string

  assert string.contains(result, "\"role\":\"user\"")
  assert string.contains(result, "\"content\":")
  assert string.contains(result, "\"text\":\"Hello!\"")
}

pub fn message_with_multiple_blocks_test() {
  let msg =
    Message(role: User, content: [
      TextBlock(text: "Check this image:"),
      ImageBlock(source: ImageSource(
        source_type: Base64,
        media_type: "image/png",
        data: "abc",
      )),
    ])
  let result = message_to_json(msg) |> json.to_string

  assert string.contains(result, "Check this image:")
  assert string.contains(result, "\"type\":\"image\"")
}

pub fn messages_to_json_test() {
  let msgs = [
    Message(role: User, content: [TextBlock(text: "Hi")]),
    Message(role: Assistant, content: [TextBlock(text: "Hello!")]),
  ]
  let result = messages_to_json(msgs) |> json.to_string

  assert string.starts_with(result, "[")
  assert string.ends_with(result, "]")
  assert string.contains(result, "\"role\":\"user\"")
  assert string.contains(result, "\"role\":\"assistant\"")
}

pub fn message_text_single_block_test() {
  let msg = Message(role: User, content: [TextBlock(text: "Hello")])
  assert message_text(msg) == "Hello"
}

pub fn message_text_multiple_blocks_test() {
  let msg =
    Message(role: User, content: [
      TextBlock(text: "Hello "),
      TextBlock(text: "World"),
    ])
  assert message_text(msg) == "Hello World"
}

pub fn message_text_with_non_text_blocks_test() {
  let msg =
    Message(role: User, content: [
      TextBlock(text: "Text"),
      ImageBlock(source: ImageSource(
        source_type: Base64,
        media_type: "image/png",
        data: "",
      )),
    ])
  assert message_text(msg) == "Text"
}

pub fn has_tool_use_true_test() {
  let msg =
    Message(role: Assistant, content: [
      TextBlock(text: "Let me help"),
      ToolUseBlock(id: "123", name: "search", input: "{}"),
    ])
  assert has_tool_use(msg) == True
}

pub fn has_tool_use_false_test() {
  let msg = Message(role: Assistant, content: [TextBlock(text: "Hello")])
  assert has_tool_use(msg) == False
}

pub fn get_tool_uses_test() {
  let tool1 = ToolUseBlock(id: "1", name: "tool1", input: "{}")
  let tool2 = ToolUseBlock(id: "2", name: "tool2", input: "{}")
  let msg =
    Message(role: Assistant, content: [
      TextBlock(text: "Using tools:"),
      tool1,
      tool2,
    ])
  let tools = get_tool_uses(msg)
  assert list.length(tools) == 2
}

// =============================================================================
// Convenience Constructor Tests
// =============================================================================

pub fn user_message_test() {
  let msg = user_message("Hello, Claude!")
  assert msg.role == User
  assert list.length(msg.content) == 1
  let assert Ok(TextBlock(text: t)) = list.first(msg.content)
  assert t == "Hello, Claude!"
}

pub fn assistant_message_test() {
  let msg = assistant_message("Hello!")
  assert msg.role == Assistant
}

pub fn text_block_test() {
  let block = TextBlock(text: "test content")
  assert block == TextBlock(text: "test content")
}

pub fn image_block_test() {
  let block =
    ImageBlock(source: ImageSource(
      source_type: Base64,
      media_type: "image/png",
      data: "base64data",
    ))
  let assert ImageBlock(source: ImageSource(
    source_type: Base64,
    media_type: mt,
    data: d,
  )) = block
  assert mt == "image/png"
  assert d == "base64data"
}

pub fn tool_use_block_test() {
  let block = ToolUseBlock(id: "id1", name: "my_tool", input: "{\"arg\":1}")
  assert block == ToolUseBlock(id: "id1", name: "my_tool", input: "{\"arg\":1}")
}

pub fn tool_result_block_test() {
  let block =
    ToolResultBlock(tool_use_id: "id1", content: "success", is_error: None)
  assert block
    == ToolResultBlock(tool_use_id: "id1", content: "success", is_error: None)
}

pub fn tool_error_block_test() {
  let block =
    ToolResultBlock(tool_use_id: "id1", content: "failed", is_error: Some(True))
  assert block
    == ToolResultBlock(
      tool_use_id: "id1",
      content: "failed",
      is_error: Some(True),
    )
}

pub fn message_constructor_test() {
  let msg =
    Message(role: User, content: [
      TextBlock(text: "Hello"),
      TextBlock(text: "World"),
    ])
  assert msg.role == User
  assert list.length(msg.content) == 2
}

// =============================================================================
// JSON String Helper Tests
// =============================================================================

pub fn message_to_json_string_test() {
  let msg = user_message("Test")
  let result = message_to_json_string(msg)
  assert string.is_empty(result) == False
  assert string.contains(result, "Test")
}

pub fn content_block_to_json_string_test() {
  let block = TextBlock(text: "Hello")
  let result = content_block_to_json_string(block)
  assert string.contains(result, "Hello")
}

// =============================================================================
// StopReason Tests
// =============================================================================

pub fn stop_reason_to_string_end_turn_test() {
  assert stop_reason_to_string(EndTurn) == "end_turn"
}

pub fn stop_reason_to_string_max_tokens_test() {
  assert stop_reason_to_string(MaxTokens) == "max_tokens"
}

pub fn stop_reason_to_string_stop_sequence_test() {
  assert stop_reason_to_string(StopSequence) == "stop_sequence"
}

pub fn stop_reason_to_string_tool_use_test() {
  assert stop_reason_to_string(ToolUse) == "tool_use"
}

pub fn stop_reason_from_string_end_turn_test() {
  assert stop_reason_from_string("end_turn") == Ok(EndTurn)
}

pub fn stop_reason_from_string_max_tokens_test() {
  assert stop_reason_from_string("max_tokens") == Ok(MaxTokens)
}

pub fn stop_reason_from_string_stop_sequence_test() {
  assert stop_reason_from_string("stop_sequence") == Ok(StopSequence)
}

pub fn stop_reason_from_string_tool_use_test() {
  assert stop_reason_from_string("tool_use") == Ok(ToolUse)
}

pub fn stop_reason_from_string_invalid_test() {
  assert stop_reason_from_string("invalid")
    == Error("Invalid stop reason: invalid")
}

pub fn stop_reason_to_json_test() {
  let result = stop_reason_to_json(EndTurn) |> json.to_string
  assert result == "\"end_turn\""
}

// =============================================================================
// Usage Tests
// =============================================================================

pub fn usage_constructor_test() {
  let u = Usage(input_tokens: 100, output_tokens: 50)
  assert u.input_tokens == 100
  assert u.output_tokens == 50
}

pub fn usage_to_json_test() {
  let u = Usage(input_tokens: 100, output_tokens: 50)
  let result = usage_to_json(u) |> json.to_string
  assert string.contains(result, "\"input_tokens\":100")
  assert string.contains(result, "\"output_tokens\":50")
}

// =============================================================================
// Metadata Tests
// =============================================================================

pub fn metadata_with_user_id_to_json_test() {
  let m = Metadata(user_id: Some("user_123"))
  let result = metadata_to_json(m) |> json.to_string
  assert string.contains(result, "\"user_id\":\"user_123\"")
}

pub fn metadata_without_user_id_to_json_test() {
  let m = Metadata(user_id: None)
  let result = metadata_to_json(m) |> json.to_string
  assert result == "{}"
}

// =============================================================================
// CreateMessageRequest Tests
// =============================================================================

pub fn create_request_basic_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
  assert req.model == "claude-sonnet-4-20250514"
  assert req.max_tokens == 1024
  assert req.system == None
  assert req.temperature == None
}

pub fn create_request_with_system_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_system("You are a helpful assistant.")
  assert req.system == Some("You are a helpful assistant.")
}

pub fn create_request_with_temperature_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_temperature(0.7)
  assert req.temperature == Some(0.7)
}

pub fn create_request_with_top_p_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_top_p(0.9)
  assert req.top_p == Some(0.9)
}

pub fn create_request_with_top_k_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_top_k(40)
  assert req.top_k == Some(40)
}

pub fn create_request_with_stop_sequences_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_stop_sequences(["END", "STOP"])
  assert req.stop_sequences == Some(["END", "STOP"])
}

pub fn create_request_with_stream_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_stream(True)
  assert req.stream == Some(True)
}

pub fn create_request_with_metadata_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_metadata(Metadata(user_id: Some("user_123")))
  let assert Some(m) = req.metadata
  assert m.user_id == Some("user_123")
}

pub fn create_request_with_user_id_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_user_id("user_456")
  let assert Some(m) = req.metadata
  assert m.user_id == Some("user_456")
}

pub fn create_request_chained_builders_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_system("Be helpful")
    |> with_temperature(0.5)
    |> with_stream(True)
  assert req.system == Some("Be helpful")
  assert req.temperature == Some(0.5)
  assert req.stream == Some(True)
}

pub fn request_to_json_basic_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hi")], 1024)
  let result = request_to_json(req) |> json.to_string

  assert string.contains(result, "\"model\":\"claude-sonnet-4-20250514\"")
  assert string.contains(result, "\"max_tokens\":1024")
  assert string.contains(result, "\"messages\":")
}

pub fn request_to_json_with_options_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hi")], 1024)
    |> with_system("Be brief")
    |> with_temperature(0.8)
  let result = request_to_json(req) |> json.to_string

  assert string.contains(result, "\"system\":\"Be brief\"")
  assert string.contains(result, "\"temperature\":0.8")
}

pub fn request_to_json_with_stop_sequences_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Hi")], 1024)
    |> with_stop_sequences(["END"])
  let result = request_to_json(req) |> json.to_string

  assert string.contains(result, "\"stop_sequences\":")
  assert string.contains(result, "\"END\"")
}

pub fn request_to_json_string_test() {
  let req =
    create_request("claude-sonnet-4-20250514", [user_message("Test")], 512)
  let result = request_to_json_string(req)

  assert string.is_empty(result) == False
  assert string.contains(result, "claude-sonnet-4-20250514")
}

// =============================================================================
// CreateMessageResponse Tests
// =============================================================================

pub fn create_response_test() {
  let resp =
    create_response(
      "msg_123",
      [TextBlock(text: "Hello!")],
      "claude-sonnet-4-20250514",
      Some(EndTurn),
      Usage(input_tokens: 10, output_tokens: 20),
    )

  assert resp.id == "msg_123"
  assert resp.response_type == "message"
  assert resp.role == Assistant
  assert resp.model == "claude-sonnet-4-20250514"
  assert resp.stop_reason == Some(EndTurn)
  assert resp.usage.input_tokens == 10
  assert resp.usage.output_tokens == 20
}

pub fn create_response_with_stop_sequence_test() {
  let resp =
    create_response_with_stop_sequence(
      "msg_456",
      [TextBlock(text: "Done")],
      "claude-sonnet-4-20250514",
      StopSequence,
      "END",
      Usage(input_tokens: 15, output_tokens: 25),
    )

  assert resp.stop_reason == Some(StopSequence)
  assert resp.stop_sequence == Some("END")
}

pub fn response_text_test() {
  let resp =
    create_response(
      "msg_123",
      [TextBlock(text: "Hello "), TextBlock(text: "World!")],
      "claude-sonnet-4-20250514",
      Some(EndTurn),
      Usage(input_tokens: 10, output_tokens: 20),
    )

  assert response_text(resp) == "Hello World!"
}

pub fn response_text_with_tool_use_test() {
  let resp =
    create_response(
      "msg_123",
      [
        TextBlock(text: "Let me help"),
        ToolUseBlock(id: "tool_1", name: "search", input: "{}"),
      ],
      "claude-sonnet-4-20250514",
      Some(ToolUse),
      Usage(input_tokens: 10, output_tokens: 20),
    )

  assert response_text(resp) == "Let me help"
}

pub fn response_has_tool_use_true_test() {
  let resp =
    create_response(
      "msg_123",
      [
        TextBlock(text: "Using tool"),
        ToolUseBlock(id: "tool_1", name: "calc", input: "{}"),
      ],
      "claude-sonnet-4-20250514",
      Some(ToolUse),
      Usage(input_tokens: 10, output_tokens: 20),
    )

  assert response_has_tool_use(resp) == True
}

pub fn response_has_tool_use_false_test() {
  let resp =
    create_response(
      "msg_123",
      [TextBlock(text: "Just text")],
      "claude-sonnet-4-20250514",
      Some(EndTurn),
      Usage(input_tokens: 10, output_tokens: 20),
    )

  assert response_has_tool_use(resp) == False
}

pub fn response_get_tool_uses_test() {
  let tool1 = ToolUseBlock(id: "t1", name: "tool1", input: "{}")
  let tool2 = ToolUseBlock(id: "t2", name: "tool2", input: "{}")
  let resp =
    create_response(
      "msg_123",
      [TextBlock(text: "Using tools"), tool1, tool2],
      "claude-sonnet-4-20250514",
      Some(ToolUse),
      Usage(input_tokens: 10, output_tokens: 20),
    )

  let tools = response_get_tool_uses(resp)
  assert list.length(tools) == 2
}

pub fn response_to_json_test() {
  let resp =
    create_response(
      "msg_123",
      [TextBlock(text: "Hello!")],
      "claude-sonnet-4-20250514",
      Some(EndTurn),
      Usage(input_tokens: 10, output_tokens: 20),
    )
  let result = response_to_json(resp) |> json.to_string

  assert string.contains(result, "\"id\":\"msg_123\"")
  assert string.contains(result, "\"type\":\"message\"")
  assert string.contains(result, "\"role\":\"assistant\"")
  assert string.contains(result, "\"model\":\"claude-sonnet-4-20250514\"")
  assert string.contains(result, "\"stop_reason\":\"end_turn\"")
  assert string.contains(result, "\"input_tokens\":10")
  assert string.contains(result, "\"output_tokens\":20")
}

pub fn response_to_json_with_stop_sequence_test() {
  let resp =
    create_response_with_stop_sequence(
      "msg_456",
      [TextBlock(text: "Done")],
      "claude-sonnet-4-20250514",
      StopSequence,
      "END",
      Usage(input_tokens: 15, output_tokens: 25),
    )
  let result = response_to_json(resp) |> json.to_string

  assert string.contains(result, "\"stop_reason\":\"stop_sequence\"")
  assert string.contains(result, "\"stop_sequence\":\"END\"")
}

pub fn response_to_json_string_test() {
  let resp =
    create_response(
      "msg_789",
      [TextBlock(text: "Test")],
      "claude-sonnet-4-20250514",
      None,
      Usage(input_tokens: 5, output_tokens: 10),
    )
  let result = response_to_json_string(resp)

  assert string.is_empty(result) == False
  assert string.contains(result, "msg_789")
}

// =============================================================================
// ApiErrorType Tests
// =============================================================================

pub fn api_error_type_from_string_authentication_test() {
  assert api_error_type_from_string("authentication_error")
    == AuthenticationError
}

pub fn api_error_type_from_string_invalid_request_test() {
  assert api_error_type_from_string("invalid_request_error")
    == InvalidRequestError
}

pub fn api_error_type_from_string_rate_limit_test() {
  assert api_error_type_from_string("rate_limit_error") == RateLimitError
}

pub fn api_error_type_from_string_api_error_test() {
  assert api_error_type_from_string("api_error") == InternalApiError
}

pub fn api_error_type_from_string_overloaded_test() {
  assert api_error_type_from_string("overloaded_error") == OverloadedError
}

pub fn api_error_type_from_string_permission_test() {
  assert api_error_type_from_string("permission_error") == PermissionError
}

pub fn api_error_type_from_string_not_found_test() {
  assert api_error_type_from_string("not_found_error") == NotFoundError
}

pub fn api_error_type_from_string_unknown_test() {
  assert api_error_type_from_string("some_new_error")
    == UnknownApiError("some_new_error")
}

pub fn api_error_type_to_string_authentication_test() {
  assert api_error_type_to_string(AuthenticationError) == "authentication_error"
}

pub fn api_error_type_to_string_invalid_request_test() {
  assert api_error_type_to_string(InvalidRequestError)
    == "invalid_request_error"
}

pub fn api_error_type_to_string_rate_limit_test() {
  assert api_error_type_to_string(RateLimitError) == "rate_limit_error"
}

pub fn api_error_type_to_string_api_error_test() {
  assert api_error_type_to_string(InternalApiError) == "api_error"
}

pub fn api_error_type_to_string_overloaded_test() {
  assert api_error_type_to_string(OverloadedError) == "overloaded_error"
}

pub fn api_error_type_to_string_unknown_test() {
  assert api_error_type_to_string(UnknownApiError("custom")) == "custom"
}

// =============================================================================
// ApiErrorDetails Tests
// =============================================================================

pub fn api_error_details_basic_test() {
  let details = api_error_details(AuthenticationError, "Invalid API key")
  assert details.error_type == AuthenticationError
  assert details.message == "Invalid API key"
  assert details.param == None
  assert details.code == None
}

pub fn api_error_details_full_test() {
  let details =
    api_error_details_full(
      InvalidRequestError,
      "Missing required field",
      Some("messages"),
      Some("MISSING_FIELD"),
    )
  assert details.error_type == InvalidRequestError
  assert details.message == "Missing required field"
  assert details.param == Some("messages")
  assert details.code == Some("MISSING_FIELD")
}

pub fn api_error_details_to_string_basic_test() {
  let details = api_error_details(RateLimitError, "Too many requests")
  let result = api_error_details_to_string(details)
  assert result == "rate_limit_error: Too many requests"
}

pub fn api_error_details_to_string_with_param_test() {
  let details =
    api_error_details_full(
      InvalidRequestError,
      "Invalid value",
      Some("temperature"),
      None,
    )
  let result = api_error_details_to_string(details)
  assert string.contains(result, "invalid_request_error")
  assert string.contains(result, "Invalid value")
  assert string.contains(result, "(param: temperature)")
}

pub fn api_error_details_to_string_with_code_test() {
  let details =
    api_error_details_full(
      InvalidRequestError,
      "Invalid value",
      None,
      Some("ERR_001"),
    )
  let result = api_error_details_to_string(details)
  assert string.contains(result, "[code: ERR_001]")
}

pub fn api_error_details_to_json_test() {
  let details = api_error_details(AuthenticationError, "Invalid key")
  let result = api_error_details_to_json(details) |> json.to_string
  assert string.contains(result, "\"type\":\"authentication_error\"")
  assert string.contains(result, "\"message\":\"Invalid key\"")
}

// =============================================================================
// Error Constructor Tests
// =============================================================================

pub fn authentication_error_constructor_test() {
  let err = authentication_error("Invalid API key")
  let assert ApiError(status_code: status, details: details) = err
  assert status == 401
  assert details.error_type == AuthenticationError
  assert details.message == "Invalid API key"
}

pub fn invalid_request_error_constructor_test() {
  let err = invalid_request_error("Missing messages field")
  let assert ApiError(status_code: status, details: details) = err
  assert status == 400
  assert details.error_type == InvalidRequestError
}

pub fn rate_limit_error_constructor_test() {
  let err = rate_limit_error("Rate limit exceeded")
  let assert ApiError(status_code: status, details: details) = err
  assert status == 429
  assert details.error_type == RateLimitError
}

pub fn internal_api_error_constructor_test() {
  let err = internal_api_error("Internal server error")
  let assert ApiError(status_code: status, details: details) = err
  assert status == 500
  assert details.error_type == InternalApiError
}

pub fn overloaded_error_constructor_test() {
  let err = overloaded_error("API is overloaded")
  let assert ApiError(status_code: status, details: details) = err
  assert status == 529
  assert details.error_type == OverloadedError
}

pub fn http_error_constructor_test() {
  let err = http_error("Connection refused")
  let assert HttpError(reason: reason) = err
  assert reason == "Connection refused"
}

pub fn json_error_constructor_test() {
  let err = json_error("Invalid JSON syntax")
  let assert JsonError(reason: reason) = err
  assert reason == "Invalid JSON syntax"
}

pub fn config_error_constructor_test() {
  let err = config_error("Invalid configuration")
  let assert ConfigError(reason: reason) = err
  assert reason == "Invalid configuration"
}

pub fn timeout_error_constructor_test() {
  let err = timeout_error(30_000)
  let assert TimeoutError(timeout_ms: ms) = err
  assert ms == 30_000
}

pub fn network_error_constructor_test() {
  let err = network_error("DNS resolution failed")
  let assert NetworkError(reason: reason) = err
  assert reason == "DNS resolution failed"
}

pub fn missing_api_key_error_constructor_test() {
  let err = missing_api_key_error()
  let assert ConfigError(reason: reason) = err
  assert string.contains(reason, "API key")
}

pub fn invalid_api_key_error_constructor_test() {
  let err = invalid_api_key_error()
  let assert ConfigError(reason: reason) = err
  assert string.contains(reason, "API key")
}

// =============================================================================
// Error Display Tests
// =============================================================================

pub fn error_to_string_api_error_test() {
  let err = authentication_error("Invalid API key")
  let result = error_to_string(err)
  assert string.contains(result, "API Error")
  assert string.contains(result, "401")
  assert string.contains(result, "authentication_error")
  assert string.contains(result, "Invalid API key")
}

pub fn error_to_string_http_error_test() {
  let err = http_error("Connection timeout")
  let result = error_to_string(err)
  assert result == "HTTP Error: Connection timeout"
}

pub fn error_to_string_json_error_test() {
  let err = json_error("Parse error at line 5")
  let result = error_to_string(err)
  assert result == "JSON Error: Parse error at line 5"
}

pub fn error_to_string_config_error_test() {
  let err = config_error("Missing API key")
  let result = error_to_string(err)
  assert result == "Configuration Error: Missing API key"
}

pub fn error_to_string_timeout_error_test() {
  let err = timeout_error(60_000)
  let result = error_to_string(err)
  assert string.contains(result, "Timeout Error")
  assert string.contains(result, "60000ms")
}

pub fn error_to_string_network_error_test() {
  let err = network_error("No route to host")
  let result = error_to_string(err)
  assert result == "Network Error: No route to host"
}

pub fn error_category_api_test() {
  let err = authentication_error("test")
  assert error_category(err) == "api"
}

pub fn error_category_http_test() {
  let err = http_error("test")
  assert error_category(err) == "http"
}

pub fn error_category_json_test() {
  let err = json_error("test")
  assert error_category(err) == "json"
}

pub fn error_category_config_test() {
  let err = config_error("test")
  assert error_category(err) == "config"
}

pub fn error_category_timeout_test() {
  let err = timeout_error(1000)
  assert error_category(err) == "timeout"
}

pub fn error_category_network_test() {
  let err = network_error("test")
  assert error_category(err) == "network"
}

// =============================================================================
// Error Predicate Tests
// =============================================================================

pub fn is_retryable_rate_limit_test() {
  let err = rate_limit_error("test")
  assert is_retryable(err) == True
}

pub fn is_retryable_overloaded_test() {
  let err = overloaded_error("test")
  assert is_retryable(err) == True
}

pub fn is_retryable_internal_api_test() {
  let err = internal_api_error("test")
  assert is_retryable(err) == True
}

pub fn is_retryable_http_test() {
  let err = http_error("test")
  assert is_retryable(err) == True
}

pub fn is_retryable_timeout_test() {
  let err = timeout_error(1000)
  assert is_retryable(err) == True
}

pub fn is_retryable_network_test() {
  let err = network_error("test")
  assert is_retryable(err) == True
}

pub fn is_retryable_auth_test() {
  let err = authentication_error("test")
  assert is_retryable(err) == False
}

pub fn is_retryable_config_test() {
  let err = config_error("test")
  assert is_retryable(err) == False
}

pub fn is_retryable_json_test() {
  let err = json_error("test")
  assert is_retryable(err) == False
}

pub fn is_authentication_error_true_test() {
  let err = authentication_error("test")
  assert is_authentication_error(err) == True
}

pub fn is_authentication_error_false_test() {
  let err = rate_limit_error("test")
  assert is_authentication_error(err) == False
}

pub fn is_rate_limit_error_true_test() {
  let err = rate_limit_error("test")
  assert is_rate_limit_error(err) == True
}

pub fn is_rate_limit_error_false_test() {
  let err = authentication_error("test")
  assert is_rate_limit_error(err) == False
}

pub fn is_overloaded_error_true_test() {
  let err = overloaded_error("test")
  assert is_overloaded_error(err) == True
}

pub fn is_overloaded_error_false_test() {
  let err = rate_limit_error("test")
  assert is_overloaded_error(err) == False
}

pub fn get_status_code_api_error_test() {
  let err = authentication_error("test")
  assert get_status_code(err) == Some(401)
}

pub fn get_status_code_http_error_test() {
  let err = http_error("test")
  assert get_status_code(err) == None
}

// =============================================================================
// Error JSON Tests
// =============================================================================

pub fn error_to_json_api_error_test() {
  let err = authentication_error("Invalid key")
  let result = error_to_json(err) |> json.to_string
  assert string.contains(result, "\"category\":\"api\"")
  assert string.contains(result, "\"status_code\":401")
  assert string.contains(result, "\"error\":")
}

pub fn error_to_json_http_error_test() {
  let err = http_error("Connection failed")
  let result = error_to_json(err) |> json.to_string
  assert string.contains(result, "\"category\":\"http\"")
  assert string.contains(result, "\"reason\":\"Connection failed\"")
}

pub fn error_to_json_json_error_test() {
  let err = json_error("Parse error")
  let result = error_to_json(err) |> json.to_string
  assert string.contains(result, "\"category\":\"json\"")
}

pub fn error_to_json_config_error_test() {
  let err = config_error("Missing config")
  let result = error_to_json(err) |> json.to_string
  assert string.contains(result, "\"category\":\"config\"")
}

pub fn error_to_json_timeout_error_test() {
  let err = timeout_error(5000)
  let result = error_to_json(err) |> json.to_string
  assert string.contains(result, "\"category\":\"timeout\"")
  assert string.contains(result, "\"timeout_ms\":5000")
}

pub fn error_to_json_network_error_test() {
  let err = network_error("DNS failed")
  let result = error_to_json(err) |> json.to_string
  assert string.contains(result, "\"category\":\"network\"")
}

pub fn error_to_json_string_test() {
  let err = rate_limit_error("Too many requests")
  let result = error_to_json_string(err)
  assert string.is_empty(result) == False
  assert string.contains(result, "rate_limit_error")
}

// =============================================================================
// Configuration Tests
// =============================================================================

fn set_env(name: String, value: String) -> Nil {
  let _ = ffi_putenv(charlist.from_string(name), charlist.from_string(value))
  Nil
}

@external(erlang, "os", "putenv")
fn ffi_putenv(name: charlist.Charlist, value: charlist.Charlist) -> Bool

pub fn load_config_from_env_test() {
  set_env("ANTHROPIC_API_KEY", "env-key")
  let assert Ok(config) = load_config(config_options())

  assert api_key_to_string(config.api_key) == "env-key"
  assert config.base_url == default_base_url
  assert config.default_model == None
  assert config.timeout_ms == default_timeout_ms
  assert config.max_retries == default_max_retries
}

pub fn load_config_prefers_explicit_values_test() {
  set_env("ANTHROPIC_API_KEY", "env-key")

  let options =
    config_options()
    |> with_api_key("explicit-key")
    |> with_base_url("https://proxy.example")
    |> with_default_model("claude-proxy")
    |> with_timeout_ms(10_000)
    |> with_max_retries(5)

  let assert Ok(config) = load_config(options)

  assert api_key_to_string(config.api_key) == "explicit-key"
  assert config.base_url == "https://proxy.example"
  assert config.default_model == Some("claude-proxy")
  assert config.timeout_ms == 10_000
  assert config.max_retries == 5
}

pub fn load_config_missing_api_key_error_test() {
  set_env("ANTHROPIC_API_KEY", "")
  let assert Error(err) = load_config(config_options())
  let assert ConfigError(reason: reason) = err

  assert string.contains(reason, "API key")
}

// =============================================================================
// Client Tests
// =============================================================================

import anthropic/client.{
  api_version, handle_response, init, init_with_key, messages_endpoint, new,
}
import gleam/http/response

pub fn client_new_test() {
  set_env("ANTHROPIC_API_KEY", "test-key")
  let assert Ok(config) = load_config(config_options())
  let client = new(config)
  assert api_key_to_string(client.config.api_key) == "test-key"
}

pub fn client_api_version_test() {
  assert api_version == "2023-06-01"
}

pub fn client_messages_endpoint_test() {
  assert messages_endpoint == "/v1/messages"
}

pub fn client_init_with_env_test() {
  // Set environment variable
  set_env("ANTHROPIC_API_KEY", "test-init-key")

  // init() should read from environment
  let assert Ok(client) = init()
  assert api_key_to_string(client.config.api_key) == "test-init-key"
}

pub fn client_init_without_env_test() {
  // Clear environment variable
  set_env("ANTHROPIC_API_KEY", "")

  // init() should fail without environment variable
  let result = init()
  assert result
    == Error(ConfigError(
      reason: "API key is required. Provide ConfigOptions.api_key or set ANTHROPIC_API_KEY.",
    ))
}

pub fn client_init_with_key_test() {
  // Clear environment variable to ensure we're using the explicit key
  set_env("ANTHROPIC_API_KEY", "")

  // init_with_key() should use the provided key
  let assert Ok(client) = init_with_key("explicit-api-key")
  assert api_key_to_string(client.config.api_key) == "explicit-api-key"
}

pub fn client_init_with_key_empty_test() {
  // init_with_key() with empty string should fail
  let result = init_with_key("")
  assert result
    == Error(ConfigError(
      reason: "API key is required. Provide ConfigOptions.api_key or set ANTHROPIC_API_KEY.",
    ))
}

pub fn client_init_with_key_overrides_env_test() {
  // Set environment variable
  set_env("ANTHROPIC_API_KEY", "env-key")

  // init_with_key() should override environment variable
  let assert Ok(client) = init_with_key("explicit-key")
  assert api_key_to_string(client.config.api_key) == "explicit-key"
}

pub fn handle_response_success_test() {
  let resp = response.new(200) |> response.set_body("{\"id\":\"test\"}")
  let result = handle_response(resp)
  assert result == Ok("{\"id\":\"test\"}")
}

pub fn handle_response_400_test() {
  let resp =
    response.new(400)
    |> response.set_body(
      "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Bad request\"}}",
    )
  let assert Error(err) = handle_response(resp)
  let assert ApiError(status_code: status, details: details) = err
  assert status == 400
  assert details.error_type == InvalidRequestError
  assert details.message == "Bad request"
}

pub fn handle_response_401_test() {
  let resp =
    response.new(401)
    |> response.set_body(
      "{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"Invalid key\"}}",
    )
  let assert Error(err) = handle_response(resp)
  let assert ApiError(status_code: status, details: details) = err
  assert status == 401
  assert details.error_type == AuthenticationError
}

pub fn handle_response_429_test() {
  let resp =
    response.new(429)
    |> response.set_body(
      "{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"Too many requests\"}}",
    )
  let assert Error(err) = handle_response(resp)
  let assert ApiError(status_code: status, details: details) = err
  assert status == 429
  assert details.error_type == RateLimitError
}

pub fn handle_response_500_test() {
  let resp =
    response.new(500)
    |> response.set_body(
      "{\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"Internal error\"}}",
    )
  let assert Error(err) = handle_response(resp)
  let assert ApiError(status_code: status, details: _) = err
  assert status == 500
}

pub fn handle_response_529_test() {
  let resp =
    response.new(529)
    |> response.set_body(
      "{\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}",
    )
  let assert Error(err) = handle_response(resp)
  let assert ApiError(status_code: status, details: details) = err
  assert status == 529
  assert details.error_type == OverloadedError
}

pub fn handle_response_fallback_error_test() {
  let resp = response.new(400) |> response.set_body("not json")
  let assert Error(err) = handle_response(resp)
  let assert ApiError(status_code: status, details: details) = err
  assert status == 400
  assert details.message == "not json"
}

// =============================================================================
// API Validation Tests
// =============================================================================

import anthropic/api.{
  type StreamError as ApiStreamError, type StreamResult as ApiStreamResult,
  ApiError as StreamApiError, EventDecodeError, HttpError as StreamHttpError,
  SseParseError, StreamResult as ApiStreamResultConstructor, chat, chat_stream,
  chat_stream_with_callback, create_message, event_text,
  stream_complete as api_stream_complete,
  stream_has_error as api_stream_has_error, stream_message_id, stream_model,
  stream_text,
}

pub fn api_validation_empty_messages_test() {
  set_env("ANTHROPIC_API_KEY", "test-key")
  let assert Ok(config) = load_config(config_options())
  let client = new(config)

  let request = create_request("claude-sonnet-4-20250514", [], 1024)
  let assert Error(err) = create_message(client, request)
  let assert ApiError(_, details) = err
  assert string.contains(details.message, "messages")
}

pub fn api_validation_empty_model_test() {
  set_env("ANTHROPIC_API_KEY", "test-key")
  let assert Ok(config) = load_config(config_options())
  let client = new(config)

  let request = create_request("", [user_message("Hello")], 1024)
  let assert Error(err) = create_message(client, request)
  let assert ApiError(_, details) = err
  assert string.contains(details.message, "model")
}

pub fn api_validation_zero_max_tokens_test() {
  set_env("ANTHROPIC_API_KEY", "test-key")
  let assert Ok(config) = load_config(config_options())
  let client = new(config)

  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 0)
  let assert Error(err) = create_message(client, request)
  let assert ApiError(_, details) = err
  assert string.contains(details.message, "max_tokens")
}

// =============================================================================
// Testing Module Tests
// =============================================================================

import anthropic/testing.{
  fixture_conversation_response, fixture_max_tokens_response,
  fixture_simple_response, fixture_stop_sequence_response,
  fixture_tool_use_response, has_api_key, mock_auth_error, mock_error_body,
  mock_error_response, mock_invalid_request_error, mock_overloaded_error,
  mock_rate_limit_error, mock_text_response, mock_text_response_body,
  mock_tool_use_response, mock_tool_use_response_body,
}

pub fn mock_text_response_test() {
  let resp = mock_text_response("Hello, world!")
  assert resp.status == 200
  assert string.contains(resp.body, "Hello, world!")
}

pub fn mock_tool_use_response_test() {
  let resp = mock_tool_use_response("tool_123", "get_weather", "{}")
  assert resp.status == 200
  assert string.contains(resp.body, "tool_123")
  assert string.contains(resp.body, "get_weather")
}

pub fn mock_error_response_test() {
  let resp = mock_error_response(400, "invalid_request_error", "Bad request")
  assert resp.status == 400
  assert string.contains(resp.body, "invalid_request_error")
  assert string.contains(resp.body, "Bad request")
}

pub fn mock_auth_error_test() {
  let resp = mock_auth_error()
  assert resp.status == 401
  assert string.contains(resp.body, "authentication_error")
}

pub fn mock_rate_limit_error_test() {
  let resp = mock_rate_limit_error()
  assert resp.status == 429
  assert string.contains(resp.body, "rate_limit_error")
}

pub fn mock_overloaded_error_test() {
  let resp = mock_overloaded_error()
  assert resp.status == 529
  assert string.contains(resp.body, "overloaded_error")
}

pub fn mock_invalid_request_error_test() {
  let resp = mock_invalid_request_error("Missing field")
  assert resp.status == 400
  assert string.contains(resp.body, "Missing field")
}

pub fn mock_text_response_body_test() {
  let body = mock_text_response_body("msg_123", "Hello!")
  assert string.contains(body, "msg_123")
  assert string.contains(body, "Hello!")
  assert string.contains(body, "end_turn")
}

pub fn mock_tool_use_response_body_test() {
  let body = mock_tool_use_response_body("msg_456", "tool_1", "search", "{}")
  assert string.contains(body, "msg_456")
  assert string.contains(body, "tool_1")
  assert string.contains(body, "search")
  assert string.contains(body, "tool_use")
}

pub fn mock_error_body_test() {
  let body = mock_error_body("rate_limit_error", "Too fast")
  assert string.contains(body, "rate_limit_error")
  assert string.contains(body, "Too fast")
}

pub fn fixture_simple_response_test() {
  let resp = fixture_simple_response()
  assert resp.id == "msg_fixture_001"
  assert resp.response_type == "message"
  assert resp.stop_reason == Some(EndTurn)
}

pub fn fixture_conversation_response_test() {
  let resp = fixture_conversation_response()
  assert resp.id == "msg_fixture_002"
  assert resp.usage.input_tokens == 150
}

pub fn fixture_tool_use_response_test() {
  let resp = fixture_tool_use_response()
  assert resp.id == "msg_fixture_003"
  assert resp.stop_reason == Some(ToolUse)
  assert list.length(resp.content) == 2
}

pub fn fixture_max_tokens_response_test() {
  let resp = fixture_max_tokens_response()
  assert resp.id == "msg_fixture_004"
  assert resp.stop_reason == Some(MaxTokens)
}

pub fn fixture_stop_sequence_response_test() {
  let resp = fixture_stop_sequence_response()
  assert resp.id == "msg_fixture_005"
  assert resp.stop_reason == Some(StopSequence)
  assert resp.stop_sequence == Some("END")
}

pub fn has_api_key_with_key_set_test() {
  // Set a key and verify has_api_key returns true
  set_env("ANTHROPIC_API_KEY", "test-key-for-has-api-key")
  let result = has_api_key()
  assert result == True
}

pub fn has_api_key_without_key_test() {
  // Clear the key and verify has_api_key returns false
  set_env("ANTHROPIC_API_KEY", "")
  let result = has_api_key()
  assert result == False
}

// =============================================================================
// Streaming Types Tests
// =============================================================================

import anthropic/types/streaming.{
  type StreamError as StreamingError, type StreamEvent, ContentBlockDeltaEvent,
  ContentBlockDeltaEventVariant, ContentBlockStartEvent, ContentBlockStopEvent,
  ErrorEvent, InputJsonContentDelta, InputJsonDelta, MessageDeltaEventVariant,
  MessageStart as StreamingMessageStart, MessageStartEvent, MessageStopEvent,
  PingEvent, StreamError as StreamingErrorConstructor, TextContentDelta,
  TextDelta, content_block_stop, event_type_from_string, event_type_string,
  get_delta_json, get_delta_text, input_json_delta, input_json_delta_event,
  is_terminal_event, message_delta_event, message_start, stream_error,
  text_block_start, text_delta, text_delta_event, tool_use_block_start,
}

pub fn text_delta_constructor_test() {
  let delta = text_delta("Hello")
  assert delta.text == "Hello"
}

pub fn input_json_delta_constructor_test() {
  let delta = input_json_delta("{\"key\":")
  assert delta.partial_json == "{\"key\":"
}

pub fn message_start_constructor_test() {
  let msg = message_start("msg_123", Assistant, "claude-3-5-haiku", 10)
  assert msg.id == "msg_123"
  assert msg.role == Assistant
  assert msg.model == "claude-3-5-haiku"
  assert msg.usage.input_tokens == 10
}

pub fn text_block_start_constructor_test() {
  let start = text_block_start(0)
  assert start.index == 0
  let assert TextBlock(text: t) = start.content_block
  assert t == ""
}

pub fn tool_use_block_start_constructor_test() {
  let start = tool_use_block_start(1, "tool_123", "get_weather")
  assert start.index == 1
  let assert ToolUseBlock(id: id, name: name, input: input) =
    start.content_block
  assert id == "tool_123"
  assert name == "get_weather"
  assert input == ""
}

pub fn text_delta_event_constructor_test() {
  let event = text_delta_event(0, "Hello")
  assert event.index == 0
  let assert TextContentDelta(delta) = event.delta
  assert delta.text == "Hello"
}

pub fn input_json_delta_event_constructor_test() {
  let event = input_json_delta_event(1, "{\"location\":")
  assert event.index == 1
  let assert InputJsonContentDelta(delta) = event.delta
  assert delta.partial_json == "{\"location\":"
}

pub fn content_block_stop_constructor_test() {
  let stop = content_block_stop(0)
  assert stop.index == 0
}

pub fn message_delta_event_constructor_test() {
  let event = message_delta_event(Some(EndTurn), None, 50)
  assert event.delta.stop_reason == Some(EndTurn)
  assert event.delta.stop_sequence == None
  assert event.usage.output_tokens == 50
}

pub fn stream_error_constructor_test() {
  let err = stream_error("overloaded_error", "Server overloaded")
  assert err.error_type == "overloaded_error"
  assert err.message == "Server overloaded"
}

pub fn event_type_string_message_start_test() {
  let event =
    MessageStartEvent(message: message_start("id", Assistant, "model", 0))
  assert event_type_string(event) == "message_start"
}

pub fn event_type_string_content_block_start_test() {
  let event = ContentBlockStartEvent(content_block_start: text_block_start(0))
  assert event_type_string(event) == "content_block_start"
}

pub fn event_type_string_content_block_delta_test() {
  let event =
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "text",
    ))
  assert event_type_string(event) == "content_block_delta"
}

pub fn event_type_string_content_block_stop_test() {
  let event = ContentBlockStopEvent(content_block_stop: content_block_stop(0))
  assert event_type_string(event) == "content_block_stop"
}

pub fn event_type_string_message_delta_test() {
  let event =
    MessageDeltaEventVariant(message_delta: message_delta_event(
      Some(EndTurn),
      None,
      10,
    ))
  assert event_type_string(event) == "message_delta"
}

pub fn event_type_string_message_stop_test() {
  assert event_type_string(MessageStopEvent) == "message_stop"
}

pub fn event_type_string_ping_test() {
  assert event_type_string(PingEvent) == "ping"
}

pub fn event_type_string_error_test() {
  let event = ErrorEvent(error: stream_error("error", "msg"))
  assert event_type_string(event) == "error"
}

pub fn event_type_from_string_valid_test() {
  assert event_type_from_string("message_start") == Ok("message_start")
  assert event_type_from_string("content_block_start")
    == Ok("content_block_start")
  assert event_type_from_string("content_block_delta")
    == Ok("content_block_delta")
  assert event_type_from_string("content_block_stop")
    == Ok("content_block_stop")
  assert event_type_from_string("message_delta") == Ok("message_delta")
  assert event_type_from_string("message_stop") == Ok("message_stop")
  assert event_type_from_string("ping") == Ok("ping")
  assert event_type_from_string("error") == Ok("error")
}

pub fn event_type_from_string_invalid_test() {
  let result = event_type_from_string("unknown")
  assert result == Error("Unknown event type: unknown")
}

pub fn is_terminal_event_message_stop_test() {
  assert is_terminal_event(MessageStopEvent) == True
}

pub fn is_terminal_event_error_test() {
  let event = ErrorEvent(error: stream_error("error", "msg"))
  assert is_terminal_event(event) == True
}

pub fn is_terminal_event_ping_test() {
  assert is_terminal_event(PingEvent) == False
}

pub fn get_delta_text_from_text_delta_test() {
  let delta = TextContentDelta(TextDelta(text: "Hello"))
  assert get_delta_text(delta) == Some("Hello")
}

pub fn get_delta_text_from_json_delta_test() {
  let delta = InputJsonContentDelta(InputJsonDelta(partial_json: "{}"))
  assert get_delta_text(delta) == None
}

pub fn get_delta_json_from_json_delta_test() {
  let delta = InputJsonContentDelta(InputJsonDelta(partial_json: "{\"key\":"))
  assert get_delta_json(delta) == Some("{\"key\":")
}

pub fn get_delta_json_from_text_delta_test() {
  let delta = TextContentDelta(TextDelta(text: "Hello"))
  assert get_delta_json(delta) == None
}

// =============================================================================
// SSE Parser Tests
// =============================================================================

import anthropic/streaming/sse.{
  EmptyEvent, flush, get_data, get_event_type, is_keepalive, new_parser_state,
  parse_chunk, parse_event, parse_event_lines, parse_line, sse_event,
}

pub fn sse_parse_simple_event_test() {
  let event_str = "event: message_start\ndata: {\"type\":\"message_start\"}"
  let assert Ok(event) = parse_event(event_str)
  assert event.event_type == Some("message_start")
  assert event.data == Some("{\"type\":\"message_start\"}")
}

pub fn sse_parse_data_only_event_test() {
  let event_str = "data: {\"text\":\"hello\"}"
  let assert Ok(event) = parse_event(event_str)
  assert event.event_type == None
  assert event.data == Some("{\"text\":\"hello\"}")
}

pub fn sse_parse_multiline_data_test() {
  let event_str = "data: line1\ndata: line2\ndata: line3"
  let assert Ok(event) = parse_event(event_str)
  assert event.data == Some("line1\nline2\nline3")
}

pub fn sse_parse_event_with_comment_test() {
  let event_str = ": this is a comment\nevent: test\ndata: value"
  let assert Ok(event) = parse_event(event_str)
  assert event.event_type == Some("test")
  assert event.data == Some("value")
}

pub fn sse_parse_empty_event_test() {
  let event_str = ""
  let result = parse_event(event_str)
  assert result == Error(EmptyEvent)
}

pub fn sse_parse_event_lines_test() {
  let lines = ["event: test", "data: hello"]
  let assert Ok(event) = parse_event_lines(lines)
  assert event.event_type == Some("test")
  assert event.data == Some("hello")
}

pub fn sse_parse_line_updates_state_test() {
  let state = new_parser_state()
  let state = parse_line(state, "event: test_event")
  assert state.current_event_type == Some("test_event")
}

pub fn sse_parse_chunk_single_event_test() {
  let chunk = "event: ping\ndata: {}\n\n"
  let result = parse_chunk(new_parser_state(), chunk)
  assert list.length(result.events) == 1
  let assert [event] = result.events
  assert event.event_type == Some("ping")
}

pub fn sse_parse_chunk_multiple_events_test() {
  let chunk =
    "event: message_start\ndata: {\"id\":1}\n\nevent: content_block_start\ndata: {\"id\":2}\n\n"
  let result = parse_chunk(new_parser_state(), chunk)
  assert list.length(result.events) == 2
}

pub fn sse_parse_chunk_partial_event_test() {
  let chunk = "event: test\ndata: partial"
  let result = parse_chunk(new_parser_state(), chunk)
  assert result.events == []
  // Buffer should contain the partial event
  assert result.state.buffer != ""
}

pub fn sse_flush_with_data_test() {
  let state =
    sse.SseParserState(
      current_event_type: None,
      current_data: [],
      current_id: None,
      current_retry: None,
      buffer: "event: final\ndata: {\"done\":true}",
    )
  let assert Ok(event) = flush(state)
  assert event.event_type == Some("final")
}

pub fn sse_flush_empty_buffer_test() {
  let state = new_parser_state()
  let result = flush(state)
  assert result == Error(EmptyEvent)
}

pub fn sse_is_keepalive_ping_test() {
  let event = sse_event(Some("ping"), None)
  assert is_keepalive(event) == True
}

pub fn sse_is_keepalive_empty_test() {
  let event = sse_event(None, None)
  assert is_keepalive(event) == True
}

pub fn sse_is_keepalive_data_test() {
  let event = sse_event(Some("message_start"), Some("{}"))
  assert is_keepalive(event) == False
}

pub fn sse_get_event_type_with_type_test() {
  let event = sse_event(Some("message_start"), Some("{}"))
  assert get_event_type(event) == "message_start"
}

pub fn sse_get_event_type_without_type_test() {
  let event = sse_event(None, Some("{}"))
  assert get_event_type(event) == "message"
}

pub fn sse_get_data_with_data_test() {
  let event = sse_event(Some("test"), Some("{\"key\":\"value\"}"))
  assert get_data(event) == "{\"key\":\"value\"}"
}

pub fn sse_get_data_without_data_test() {
  let event = sse_event(Some("ping"), None)
  assert get_data(event) == ""
}

// =============================================================================
// Streaming Decoder Tests
// =============================================================================

import anthropic/streaming/decoder.{
  JsonParseError, UnknownEventType, decode_event,
}

pub fn decode_ping_event_test() {
  let sse_event = sse_event(Some("ping"), None)
  let assert Ok(event) = decode_event(sse_event)
  assert event == PingEvent
}

pub fn decode_message_stop_event_test() {
  let sse_event = sse_event(Some("message_stop"), None)
  let assert Ok(event) = decode_event(sse_event)
  assert event == MessageStopEvent
}

pub fn decode_message_start_event_test() {
  let data =
    "{\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-3\",\"usage\":{\"input_tokens\":10}}}"
  let sse_event = sse_event(Some("message_start"), Some(data))
  let assert Ok(MessageStartEvent(msg)) = decode_event(sse_event)
  assert msg.id == "msg_123"
  assert msg.model == "claude-3"
  assert msg.usage.input_tokens == 10
}

pub fn decode_content_block_start_text_test() {
  let data =
    "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}"
  let sse_event = sse_event(Some("content_block_start"), Some(data))
  let assert Ok(ContentBlockStartEvent(start)) = decode_event(sse_event)
  assert start.index == 0
  let assert TextBlock(text: t) = start.content_block
  assert t == ""
}

pub fn decode_content_block_start_tool_use_test() {
  let data =
    "{\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tool_123\",\"name\":\"get_weather\"}}"
  let sse_event = sse_event(Some("content_block_start"), Some(data))
  let assert Ok(ContentBlockStartEvent(start)) = decode_event(sse_event)
  assert start.index == 1
  let assert ToolUseBlock(id: id, name: name, input: _) = start.content_block
  assert id == "tool_123"
  assert name == "get_weather"
}

pub fn decode_content_block_delta_text_test() {
  let data =
    "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}"
  let sse_event = sse_event(Some("content_block_delta"), Some(data))
  let assert Ok(ContentBlockDeltaEventVariant(delta_event)) =
    decode_event(sse_event)
  assert delta_event.index == 0
  let assert TextContentDelta(delta) = delta_event.delta
  assert delta.text == "Hello"
}

pub fn decode_content_block_delta_json_test() {
  let data =
    "{\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"loc\\\"\"}}"
  let sse_event = sse_event(Some("content_block_delta"), Some(data))
  let assert Ok(ContentBlockDeltaEventVariant(delta_event)) =
    decode_event(sse_event)
  assert delta_event.index == 1
  let assert InputJsonContentDelta(delta) = delta_event.delta
  assert delta.partial_json == "{\"loc\""
}

pub fn decode_content_block_stop_test() {
  let data = "{\"type\":\"content_block_stop\",\"index\":0}"
  let sse_event = sse_event(Some("content_block_stop"), Some(data))
  let assert Ok(ContentBlockStopEvent(stop)) = decode_event(sse_event)
  assert stop.index == 0
}

pub fn decode_message_delta_test() {
  let data =
    "{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":25}}"
  let sse_event = sse_event(Some("message_delta"), Some(data))
  let assert Ok(MessageDeltaEventVariant(delta)) = decode_event(sse_event)
  assert delta.delta.stop_reason == Some(EndTurn)
  assert delta.usage.output_tokens == 25
}

pub fn decode_error_event_test() {
  let data =
    "{\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Server busy\"}}"
  let sse_event = sse_event(Some("error"), Some(data))
  let assert Ok(ErrorEvent(err)) = decode_event(sse_event)
  assert err.error_type == "overloaded_error"
  assert err.message == "Server busy"
}

pub fn decode_unknown_event_type_test() {
  let sse_event = sse_event(Some("unknown_event"), Some("{}"))
  let assert Error(UnknownEventType(t)) = decode_event(sse_event)
  assert t == "unknown_event"
}

pub fn decode_invalid_json_test() {
  let sse_event = sse_event(Some("message_start"), Some("not valid json"))
  let assert Error(JsonParseError(_)) = decode_event(sse_event)
}

// =============================================================================
// Stream Accumulator Tests
// =============================================================================

import anthropic/streaming/accumulator.{
  accumulate, build_response, get_accumulated_text, has_content,
  has_error as accumulator_has_error, new as new_accumulator, process_event,
  process_events, total_tokens,
}

pub fn accumulator_new_test() {
  let state = new_accumulator()
  assert state.id == None
  assert state.is_complete == False
  assert state.input_tokens == 0
  assert state.output_tokens == 0
}

pub fn accumulator_process_message_start_test() {
  let state = new_accumulator()
  let event =
    MessageStartEvent(message: message_start(
      "msg_123",
      Assistant,
      "claude-3",
      15,
    ))
  let state = process_event(state, event)
  assert state.id == Some("msg_123")
  assert state.model == Some("claude-3")
  assert state.input_tokens == 15
}

pub fn accumulator_process_content_block_start_test() {
  let state = new_accumulator()
  let event = ContentBlockStartEvent(content_block_start: text_block_start(0))
  let state = process_event(state, event)
  assert has_content(state) == True
}

pub fn accumulator_process_content_block_delta_test() {
  let state = new_accumulator()
  let start_event =
    ContentBlockStartEvent(content_block_start: text_block_start(0))
  let delta_event =
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "Hello",
    ))
  let state = process_event(state, start_event)
  let state = process_event(state, delta_event)
  assert get_accumulated_text(state) == "Hello"
}

pub fn accumulator_process_multiple_deltas_test() {
  let state = new_accumulator()
  let start_event =
    ContentBlockStartEvent(content_block_start: text_block_start(0))
  let delta1 =
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "Hello",
    ))
  let delta2 =
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      " World",
    ))
  let state = process_event(state, start_event)
  let state = process_event(state, delta1)
  let state = process_event(state, delta2)
  assert get_accumulated_text(state) == "Hello World"
}

pub fn accumulator_process_message_delta_test() {
  let state = new_accumulator()
  let event =
    MessageDeltaEventVariant(message_delta: message_delta_event(
      Some(EndTurn),
      None,
      50,
    ))
  let state = process_event(state, event)
  assert state.stop_reason == Some(EndTurn)
  assert state.output_tokens == 50
}

pub fn accumulator_process_message_stop_test() {
  let state = new_accumulator()
  let event = MessageStopEvent
  let state = process_event(state, event)
  assert state.is_complete == True
}

pub fn accumulator_process_ping_test() {
  let state = new_accumulator()
  let event = PingEvent
  let new_state = process_event(state, event)
  // Ping should not change state
  assert new_state.id == state.id
  assert new_state.is_complete == state.is_complete
}

pub fn accumulator_process_error_test() {
  let state = new_accumulator()
  let event = ErrorEvent(error: stream_error("error", "Something went wrong"))
  let state = process_event(state, event)
  assert accumulator_has_error(state) == True
}

pub fn accumulator_process_events_test() {
  let events = [
    MessageStartEvent(message: message_start("msg_1", Assistant, "claude-3", 10)),
    ContentBlockStartEvent(content_block_start: text_block_start(0)),
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(0, "Hi")),
    ContentBlockStopEvent(content_block_stop: content_block_stop(0)),
    MessageDeltaEventVariant(message_delta: message_delta_event(
      Some(EndTurn),
      None,
      5,
    )),
    MessageStopEvent,
  ]
  let state = process_events(events)
  assert state.id == Some("msg_1")
  assert state.is_complete == True
  assert get_accumulated_text(state) == "Hi"
  assert state.input_tokens == 10
  assert state.output_tokens == 5
}

pub fn accumulator_build_response_test() {
  let events = [
    MessageStartEvent(message: message_start(
      "msg_build",
      Assistant,
      "claude-3",
      20,
    )),
    ContentBlockStartEvent(content_block_start: text_block_start(0)),
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "Response text",
    )),
    ContentBlockStopEvent(content_block_stop: content_block_stop(0)),
    MessageDeltaEventVariant(message_delta: message_delta_event(
      Some(EndTurn),
      None,
      15,
    )),
    MessageStopEvent,
  ]
  let state = process_events(events)
  let assert Ok(response) = build_response(state)
  assert response.id == "msg_build"
  assert response.model == "claude-3"
  assert response.stop_reason == Some(EndTurn)
  assert response.usage.input_tokens == 20
  assert response.usage.output_tokens == 15
  assert response_text(response) == "Response text"
}

pub fn accumulator_build_response_missing_id_test() {
  let state = new_accumulator()
  let result = build_response(state)
  assert result == Error("Missing message ID")
}

pub fn accumulate_convenience_test() {
  let events = [
    MessageStartEvent(message: message_start("msg_acc", Assistant, "model", 5)),
    ContentBlockStartEvent(content_block_start: text_block_start(0)),
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "Test",
    )),
    MessageDeltaEventVariant(message_delta: message_delta_event(
      Some(EndTurn),
      None,
      3,
    )),
    MessageStopEvent,
  ]
  let assert Ok(response) = accumulate(events)
  assert response.id == "msg_acc"
  assert response_text(response) == "Test"
}

pub fn accumulator_total_tokens_test() {
  let state = new_accumulator()
  let event1 =
    MessageStartEvent(message: message_start("id", Assistant, "model", 100))
  let event2 =
    MessageDeltaEventVariant(message_delta: message_delta_event(
      Some(EndTurn),
      None,
      50,
    ))
  let state = process_event(state, event1)
  let state = process_event(state, event2)
  assert total_tokens(state) == 150
}

// =============================================================================
// Streaming Handler Tests
// =============================================================================

import anthropic/streaming/handler.{
  build_stream_result, finalize_stream, get_accumulated_events, get_event_text,
  get_full_text, get_message_id, get_model, get_stream_error, get_text_deltas,
  has_error as stream_has_error, has_stream_error, is_complete,
  is_stream_complete, new_streaming_state, process_chunk,
}

pub fn handler_get_text_deltas_test() {
  let events = [
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "Hello",
    )),
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(0, " ")),
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "World",
    )),
  ]
  let deltas = get_text_deltas(events)
  assert deltas == ["Hello", " ", "World"]
}

pub fn handler_get_full_text_test() {
  let events = [
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "Hello",
    )),
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(0, " ")),
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "World",
    )),
  ]
  assert get_full_text(events) == "Hello World"
}

pub fn handler_get_message_id_test() {
  let events = [
    MessageStartEvent(message: message_start(
      "msg_handler",
      Assistant,
      "model",
      0,
    )),
    MessageStopEvent,
  ]
  assert get_message_id(events) == Ok("msg_handler")
}

pub fn handler_get_message_id_missing_test() {
  let events = [MessageStopEvent]
  assert get_message_id(events) == Error(Nil)
}

pub fn handler_get_model_test() {
  let events = [
    MessageStartEvent(message: message_start(
      "id",
      Assistant,
      "claude-3-5-haiku",
      0,
    )),
  ]
  assert get_model(events) == Ok("claude-3-5-haiku")
}

pub fn handler_is_complete_true_test() {
  let events = [
    MessageStartEvent(message: message_start("id", Assistant, "model", 0)),
    MessageStopEvent,
  ]
  assert is_complete(events) == True
}

pub fn handler_is_complete_false_test() {
  let events = [
    MessageStartEvent(message: message_start("id", Assistant, "model", 0)),
  ]
  assert is_complete(events) == False
}

pub fn handler_has_error_true_test() {
  let events = [
    MessageStartEvent(message: message_start("id", Assistant, "model", 0)),
    ErrorEvent(error: stream_error("error", "oops")),
  ]
  assert stream_has_error(events) == True
}

pub fn handler_has_error_false_test() {
  let events = [
    MessageStartEvent(message: message_start("id", Assistant, "model", 0)),
    MessageStopEvent,
  ]
  assert stream_has_error(events) == False
}

// =============================================================================
// Incremental Streaming Tests (Sans-IO Real-Time Streaming)
// =============================================================================

pub fn handler_new_streaming_state_test() {
  let state = new_streaming_state()
  assert is_stream_complete(state) == False
  assert has_stream_error(state) == False
  assert get_accumulated_events(state) == []
}

pub fn handler_process_chunk_empty_test() {
  let state = new_streaming_state()
  let #(events, new_state) = process_chunk(state, "")
  assert events == []
  assert is_stream_complete(new_state) == False
}

pub fn handler_process_chunk_single_event_test() {
  let state = new_streaming_state()
  let sse_data =
    "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-5-haiku\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":10,\"output_tokens\":0}}}\n\n"
  let #(events, new_state) = process_chunk(state, sse_data)
  assert list.length(events) == 1
  assert is_stream_complete(new_state) == False
}

pub fn handler_process_chunk_text_delta_test() {
  let state = new_streaming_state()
  let sse_data =
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n"
  let #(events, new_state) = process_chunk(state, sse_data)
  assert list.length(events) == 1
  case list.first(events) {
    Ok(event) -> {
      case get_event_text(event) {
        Ok(text) -> {
          assert text == "Hello"
        }
        Error(_) -> {
          assert False
        }
      }
    }
    Error(_) -> {
      assert False
    }
  }
  assert is_stream_complete(new_state) == False
}

pub fn handler_process_chunk_multiple_chunks_test() {
  // Simulate incremental streaming with multiple chunks
  let state = new_streaming_state()

  // First chunk - partial event
  let chunk1 =
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n"
  let #(events1, state1) = process_chunk(state, chunk1)
  assert list.length(events1) == 1

  // Second chunk - another event
  let chunk2 =
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" World\"}}\n\n"
  let #(events2, state2) = process_chunk(state1, chunk2)
  assert list.length(events2) == 1

  // Accumulated events should have both
  let accumulated = get_accumulated_events(state2)
  assert list.length(accumulated) == 2
}

pub fn handler_process_chunk_message_stop_completes_stream_test() {
  let state = new_streaming_state()
  let sse_data = "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  let #(events, new_state) = process_chunk(state, sse_data)
  assert list.length(events) == 1
  assert is_stream_complete(new_state) == True
}

pub fn handler_get_event_text_success_test() {
  let event =
    ContentBlockDeltaEventVariant(content_block_delta: text_delta_event(
      0,
      "Hello",
    ))
  assert get_event_text(event) == Ok("Hello")
}

pub fn handler_get_event_text_non_text_event_test() {
  let event = MessageStopEvent
  assert get_event_text(event) == Error(Nil)
}

pub fn handler_get_event_text_message_start_test() {
  let event =
    MessageStartEvent(message: message_start("id", Assistant, "model", 0))
  assert get_event_text(event) == Error(Nil)
}

pub fn handler_finalize_stream_empty_test() {
  let state = new_streaming_state()
  let remaining = finalize_stream(state)
  assert remaining == []
}

pub fn handler_build_stream_result_test() {
  let state = new_streaming_state()
  let sse_data =
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Test\"}}\n\n"
  let #(_events, state_with_events) = process_chunk(state, sse_data)
  let result = build_stream_result(state_with_events)
  assert list.length(result.events) == 1
}

pub fn handler_is_stream_complete_initially_false_test() {
  let state = new_streaming_state()
  assert is_stream_complete(state) == False
}

pub fn handler_has_stream_error_initially_false_test() {
  let state = new_streaming_state()
  assert has_stream_error(state) == False
}

pub fn handler_get_stream_error_initially_none_test() {
  let state = new_streaming_state()
  assert get_stream_error(state) == None
}

pub fn handler_process_chunk_accumulates_events_test() {
  let state = new_streaming_state()

  // Process first chunk
  let chunk1 =
    "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3-5-haiku\",\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}\n\n"
  let #(_events1, state1) = process_chunk(state, chunk1)

  // Process second chunk
  let chunk2 =
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}\n\n"
  let #(_events2, state2) = process_chunk(state1, chunk2)

  // Process final chunk
  let chunk3 = "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  let #(_events3, final_state) = process_chunk(state2, chunk3)

  // Should have accumulated all events
  let all_events = get_accumulated_events(final_state)
  assert list.length(all_events) == 3
  assert is_stream_complete(final_state) == True
}

pub fn handler_realtime_text_extraction_pattern_test() {
  // This test demonstrates the real-time streaming pattern
  // where text is extracted from each chunk as it arrives
  let state = new_streaming_state()

  let chunk1 =
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n"
  let #(events1, state1) = process_chunk(state, chunk1)

  // Extract text from first chunk in real-time
  let text1 =
    events1
    |> list.filter_map(get_event_text)
    |> string.join("")
  assert text1 == "Hello"

  let chunk2 =
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" World\"}}\n\n"
  let #(events2, _state2) = process_chunk(state1, chunk2)

  // Extract text from second chunk in real-time
  let text2 =
    events2
    |> list.filter_map(get_event_text)
    |> string.join("")
  assert text2 == " World"
}

// =============================================================================
// Tool Types Tests (Issue #13)
// =============================================================================

pub fn property_simple_test() {
  let prop = property("string")
  assert prop.property_type == "string"
  assert prop.description == None
  assert prop.enum_values == None
}

pub fn property_with_description_test() {
  let prop = property_with_description("string", "A location")
  assert prop.property_type == "string"
  assert prop.description == Some("A location")
}

pub fn enum_property_test() {
  let prop = enum_property(Some("Temperature unit"), ["celsius", "fahrenheit"])
  assert prop.property_type == "string"
  assert prop.enum_values == Some(["celsius", "fahrenheit"])
}

pub fn array_property_test() {
  let item_schema = property("string")
  let prop = array_property(Some("List of items"), item_schema)
  assert prop.property_type == "array"
  assert prop.items != None
}

pub fn object_property_test() {
  let props = [#("name", property("string"))]
  let prop = object_property(Some("A person"), props, ["name"])
  assert prop.property_type == "object"
  assert prop.properties == Some(props)
  assert prop.required == Some(["name"])
}

pub fn property_schema_to_json_test() {
  let prop = property_with_description("string", "A description")
  let json_str = property_schema_to_json(prop) |> json.to_string
  assert string.contains(json_str, "\"type\":\"string\"")
  assert string.contains(json_str, "\"description\":\"A description\"")
}

pub fn input_schema_empty_test() {
  let schema = empty_input_schema()
  assert schema.schema_type == "object"
  assert schema.properties == None
  assert schema.required == None
}

pub fn input_schema_with_properties_test() {
  let props = [#("location", property_with_description("string", "City name"))]
  let schema = input_schema(props, ["location"])
  assert schema.schema_type == "object"
  assert schema.properties != None
  assert schema.required == Some(["location"])
}

pub fn input_schema_to_json_test() {
  let props = [#("location", property("string"))]
  let schema = input_schema(props, ["location"])
  let json_str = input_schema_to_json(schema) |> json.to_string
  assert string.contains(json_str, "\"type\":\"object\"")
  assert string.contains(json_str, "\"properties\"")
  assert string.contains(json_str, "\"required\"")
}

pub fn tool_simple_test() {
  let t =
    Tool(
      name: tool_name_unchecked("get_time"),
      description: None,
      input_schema: empty_input_schema(),
    )
  assert tool_name_to_string(t.name) == "get_time"
  assert t.description == None
}

pub fn tool_with_description_test() {
  let t =
    Tool(
      name: tool_name_unchecked("get_time"),
      description: Some("Get current time"),
      input_schema: empty_input_schema(),
    )
  assert tool_name_to_string(t.name) == "get_time"
  assert t.description == Some("Get current time")
}

pub fn tool_to_json_test() {
  let t =
    Tool(
      name: tool_name_unchecked("get_weather"),
      description: Some("Get weather"),
      input_schema: empty_input_schema(),
    )
  let json_str = tool_to_json(t) |> json.to_string
  assert string.contains(json_str, "\"name\":\"get_weather\"")
  assert string.contains(json_str, "\"description\":\"Get weather\"")
  assert string.contains(json_str, "\"input_schema\"")
}

pub fn tool_to_json_string_test() {
  let t =
    Tool(
      name: tool_name_unchecked("my_tool"),
      description: None,
      input_schema: empty_input_schema(),
    )
  let json_str = tool_to_json_string(t)
  assert string.contains(json_str, "\"name\":\"my_tool\"")
}

pub fn tools_to_json_test() {
  let t1 =
    Tool(
      name: tool_name_unchecked("tool1"),
      description: None,
      input_schema: empty_input_schema(),
    )
  let t2 =
    Tool(
      name: tool_name_unchecked("tool2"),
      description: None,
      input_schema: empty_input_schema(),
    )
  let json_str = tools_to_json([t1, t2]) |> json.to_string
  assert string.contains(json_str, "\"name\":\"tool1\"")
  assert string.contains(json_str, "\"name\":\"tool2\"")
}

// =============================================================================
// Tool Choice Tests
// =============================================================================

pub fn tool_choice_auto_test() {
  let choice = Auto
  let json_str = tool_choice_to_json(choice) |> json.to_string
  assert string.contains(json_str, "\"type\":\"auto\"")
}

pub fn tool_choice_any_test() {
  let choice = Any
  let json_str = tool_choice_to_json(choice) |> json.to_string
  assert string.contains(json_str, "\"type\":\"any\"")
}

pub fn tool_choice_none_test() {
  let choice = NoTool
  let json_str = tool_choice_to_json(choice) |> json.to_string
  assert string.contains(json_str, "\"type\":\"none\"")
}

pub fn tool_choice_specific_test() {
  let choice = SpecificTool(name: "get_weather")
  let json_str = tool_choice_to_json(choice) |> json.to_string
  assert string.contains(json_str, "\"type\":\"tool\"")
  assert string.contains(json_str, "\"name\":\"get_weather\"")
}

// =============================================================================
// Tool Call and Result Tests
// =============================================================================

pub fn tool_call_test() {
  let call =
    ToolCall(
      id: "id_123",
      name: "get_weather",
      input: "{\"location\": \"Paris\"}",
    )
  assert call.id == "id_123"
  assert call.name == "get_weather"
  assert call.input == "{\"location\": \"Paris\"}"
}

pub fn tool_success_test() {
  let result = ToolSuccess(tool_use_id: "id_123", content: "Sunny, 25C")
  let assert ToolSuccess(tool_use_id, content) = result
  assert tool_use_id == "id_123"
  assert content == "Sunny, 25C"
}

pub fn tool_failure_test() {
  let result = ToolFailure(tool_use_id: "id_123", error: "Location not found")
  let assert ToolFailure(tool_use_id, error) = result
  assert tool_use_id == "id_123"
  assert error == "Location not found"
}

// =============================================================================
// Request with Tools Tests (Issue #14)
// =============================================================================

pub fn request_with_tools_test() {
  let t =
    Tool(
      name: tool_name_unchecked("get_weather"),
      description: None,
      input_schema: empty_input_schema(),
    )
  let req =
    create_request("claude-3-5-haiku-20241022", [user_message("Hello")], 100)
    |> with_tools([t])

  assert req.tools == Some([t])
}

pub fn request_with_tool_choice_test() {
  let req =
    create_request("claude-3-5-haiku-20241022", [user_message("Hello")], 100)
    |> with_tool_choice(Auto)

  assert req.tool_choice == Some(Auto)
}

pub fn request_with_tools_and_choice_test() {
  let t =
    Tool(
      name: tool_name_unchecked("get_weather"),
      description: None,
      input_schema: empty_input_schema(),
    )
  let req =
    create_request("claude-3-5-haiku-20241022", [user_message("Hello")], 100)
    |> with_tools_and_choice([t], Any)

  assert req.tools == Some([t])
  assert req.tool_choice == Some(Any)
}

pub fn request_with_tools_to_json_test() {
  let t =
    Tool(
      name: tool_name_unchecked("get_weather"),
      description: Some("Get weather"),
      input_schema: empty_input_schema(),
    )
  let req =
    create_request("claude-3-5-haiku-20241022", [user_message("Hello")], 100)
    |> with_tools([t])
    |> with_tool_choice(Auto)

  let json_str = request_to_json_string(req)
  assert string.contains(json_str, "\"tools\"")
  assert string.contains(json_str, "\"name\":\"get_weather\"")
  assert string.contains(json_str, "\"tool_choice\"")
  assert string.contains(json_str, "\"type\":\"auto\"")
}

// =============================================================================
// Tool Use Response Tests (Issue #15)
// =============================================================================

import anthropic/tools.{
  build_continuation_messages, build_tool_result_messages, count_tool_calls,
  create_tool_result_message, dispatch_tool_call, dispatch_tool_calls,
  execute_tool_calls, extract_tool_calls, failure_for_call, get_first_tool_call,
  get_tool_call_by_id, get_tool_calls_by_name, get_tool_names, has_tool_call,
  needs_tool_execution, success_for_call, tool_result_to_content_block,
}

fn create_tool_use_response() -> request.CreateMessageResponse {
  create_response(
    "msg_123",
    [
      ToolUseBlock(
        id: "toolu_1",
        name: "get_weather",
        input: "{\"location\":\"Paris\"}",
      ),
      TextBlock(text: "Let me check the weather."),
      ToolUseBlock(id: "toolu_2", name: "get_time", input: "{}"),
    ],
    "claude-3-5-haiku-20241022",
    Some(ToolUse),
    Usage(input_tokens: 10, output_tokens: 20),
  )
}

pub fn needs_tool_execution_true_test() {
  let response = create_tool_use_response()
  assert needs_tool_execution(response) == True
}

pub fn needs_tool_execution_false_test() {
  let response =
    create_response(
      "msg_123",
      [TextBlock(text: "Hello!")],
      "claude-3-5-haiku-20241022",
      Some(EndTurn),
      Usage(input_tokens: 10, output_tokens: 20),
    )
  assert needs_tool_execution(response) == False
}

pub fn extract_tool_calls_test() {
  let response = create_tool_use_response()
  let calls = extract_tool_calls(response)
  assert list.length(calls) == 2

  let assert [first, second] = calls
  assert first.id == "toolu_1"
  assert first.name == "get_weather"
  assert second.id == "toolu_2"
  assert second.name == "get_time"
}

pub fn get_tool_call_by_id_found_test() {
  let response = create_tool_use_response()
  let result = get_tool_call_by_id(response, "toolu_1")
  let assert Ok(call) = result
  assert call.name == "get_weather"
}

pub fn get_tool_call_by_id_not_found_test() {
  let response = create_tool_use_response()
  let result = get_tool_call_by_id(response, "nonexistent")
  assert result == Error(Nil)
}

pub fn get_tool_calls_by_name_test() {
  let response = create_tool_use_response()
  let calls = get_tool_calls_by_name(response, "get_weather")
  assert list.length(calls) == 1
  let assert [call] = calls
  assert call.id == "toolu_1"
}

pub fn get_first_tool_call_test() {
  let response = create_tool_use_response()
  let result = get_first_tool_call(response)
  let assert Ok(call) = result
  assert call.id == "toolu_1"
}

pub fn count_tool_calls_test() {
  let response = create_tool_use_response()
  assert count_tool_calls(response) == 2
}

pub fn get_tool_names_test() {
  let response = create_tool_use_response()
  let names = get_tool_names(response)
  assert list.contains(names, "get_weather")
  assert list.contains(names, "get_time")
}

pub fn has_tool_call_true_test() {
  let response = create_tool_use_response()
  assert has_tool_call(response, "get_weather") == True
}

pub fn has_tool_call_false_test() {
  let response = create_tool_use_response()
  assert has_tool_call(response, "nonexistent") == False
}

// =============================================================================
// Tool Result Submission Tests (Issue #16)
// =============================================================================

pub fn tool_result_to_content_block_success_test() {
  let result = ToolSuccess(tool_use_id: "id_1", content: "Sunny, 25C")
  let block = tool_result_to_content_block(result)
  let assert ToolResultBlock(tool_use_id, content, is_error) = block
  assert tool_use_id == "id_1"
  assert content == "Sunny, 25C"
  assert is_error == None
}

pub fn tool_result_to_content_block_failure_test() {
  let result = ToolFailure(tool_use_id: "id_1", error: "Error occurred")
  let block = tool_result_to_content_block(result)
  let assert ToolResultBlock(tool_use_id, content, is_error) = block
  assert tool_use_id == "id_1"
  assert content == "Error occurred"
  assert is_error == Some(True)
}

pub fn create_tool_result_message_test() {
  let results = [
    ToolSuccess(tool_use_id: "id_1", content: "Result 1"),
    ToolFailure(tool_use_id: "id_2", error: "Error 2"),
  ]
  let msg = create_tool_result_message(results)
  assert msg.role == User
  assert list.length(msg.content) == 2
}

pub fn build_tool_result_messages_test() {
  let original = [user_message("What's the weather?")]
  let response = create_tool_use_response()
  let results = [ToolSuccess(tool_use_id: "toolu_1", content: "Sunny")]

  let messages = build_tool_result_messages(original, response, results)
  assert list.length(messages) == 3
  // Original user message
  let assert [first, second, third] = messages
  assert first.role == User
  // Assistant response with tool use
  assert second.role == Assistant
  // User tool results
  assert third.role == User
}

pub fn build_continuation_messages_test() {
  let response = create_tool_use_response()
  let results = [ToolSuccess(tool_use_id: "toolu_1", content: "Sunny")]

  let messages = build_continuation_messages(response, results)
  assert list.length(messages) == 2
  let assert [first, second] = messages
  assert first.role == Assistant
  assert second.role == User
}

pub fn success_for_call_test() {
  let call = ToolCall(id: "id_1", name: "tool", input: "{}")
  let result = success_for_call(call, "Success content")
  let assert ToolSuccess(tool_use_id, content) = result
  assert tool_use_id == "id_1"
  assert content == "Success content"
}

pub fn failure_for_call_test() {
  let call = ToolCall(id: "id_1", name: "tool", input: "{}")
  let result = failure_for_call(call, "Error message")
  let assert ToolFailure(tool_use_id, error) = result
  assert tool_use_id == "id_1"
  assert error == "Error message"
}

pub fn execute_tool_calls_test() {
  let calls = [
    ToolCall(id: "id_1", name: "tool1", input: "{}"),
    ToolCall(id: "id_2", name: "tool2", input: "{}"),
  ]

  let handler = fn(call: ToolCall) {
    case call.name {
      "tool1" -> Ok("Result 1")
      _ -> Error("Unknown tool")
    }
  }

  let results = execute_tool_calls(calls, handler)
  assert list.length(results) == 2

  let assert [first, second] = results
  let assert ToolSuccess(_, content) = first
  assert content == "Result 1"

  let assert ToolFailure(_, error) = second
  assert error == "Unknown tool"
}

pub fn dispatch_tool_call_found_test() {
  let call = ToolCall(id: "id_1", name: "get_weather", input: "{}")
  let handlers = [
    #("get_weather", fn(_input: String) { Ok("Sunny") }),
    #("get_time", fn(_input: String) { Ok("12:00") }),
  ]

  let result = dispatch_tool_call(call, handlers)
  let assert ToolSuccess(_, content) = result
  assert content == "Sunny"
}

pub fn dispatch_tool_call_not_found_test() {
  let call = ToolCall(id: "id_1", name: "unknown_tool", input: "{}")
  let handlers = [#("get_weather", fn(_input: String) { Ok("Sunny") })]

  let result = dispatch_tool_call(call, handlers)
  let assert ToolFailure(_, error) = result
  assert string.contains(error, "Unknown tool")
}

pub fn dispatch_tool_calls_test() {
  let calls = [
    ToolCall(id: "id_1", name: "get_weather", input: "{}"),
    ToolCall(id: "id_2", name: "get_time", input: "{}"),
  ]
  let handlers = [
    #("get_weather", fn(_input: String) { Ok("Sunny") }),
    #("get_time", fn(_input: String) { Ok("12:00") }),
  ]

  let results = dispatch_tool_calls(calls, handlers)
  assert list.length(results) == 2

  let assert [first, second] = results
  let assert ToolSuccess(_, c1) = first
  assert c1 == "Sunny"
  let assert ToolSuccess(_, c2) = second
  assert c2 == "12:00"
}

// =============================================================================
// Tool Builder Tests (Issue #17)
// =============================================================================

import anthropic/tools/builder.{
  InvalidToolName, add_boolean_param, add_enum_param, add_integer_param,
  add_number_param, add_object_param, add_string_array_param, add_string_param,
  build, build_simple, build_validated, tool_builder,
  tool_builder_with_description, with_description as builder_with_description,
}

pub fn tool_builder_simple_test() {
  let t =
    tool_builder("get_time")
    |> build_simple

  assert tool_name_to_string(t.name) == "get_time"
  assert t.description == None
  assert t.input_schema.properties == None
}

pub fn tool_builder_with_description_init_test() {
  let t =
    tool_builder_with_description("get_time", "Get current time")
    |> build_simple

  assert tool_name_to_string(t.name) == "get_time"
  assert t.description == Some("Get current time")
}

pub fn tool_builder_add_description_test() {
  let t =
    tool_builder("get_time")
    |> builder_with_description("Get current time")
    |> build_simple

  assert t.description == Some("Get current time")
}

pub fn tool_builder_string_param_test() {
  let t =
    tool_builder("get_weather")
    |> add_string_param("location", "City name", True)
    |> build

  assert t.input_schema.properties != None
  assert t.input_schema.required == Some(["location"])
}

pub fn tool_builder_number_param_test() {
  let t =
    tool_builder("calculate")
    |> add_number_param("value", "A number", True)
    |> build

  let assert Some(props) = t.input_schema.properties
  let assert [#("value", prop)] = props
  assert prop.property_type == "number"
}

pub fn tool_builder_integer_param_test() {
  let t =
    tool_builder("count")
    |> add_integer_param("count", "An integer", True)
    |> build

  let assert Some(props) = t.input_schema.properties
  let assert [#("count", prop)] = props
  assert prop.property_type == "integer"
}

pub fn tool_builder_boolean_param_test() {
  let t =
    tool_builder("toggle")
    |> add_boolean_param("enabled", "Enable feature", False)
    |> build

  let assert Some(props) = t.input_schema.properties
  let assert [#("enabled", prop)] = props
  assert prop.property_type == "boolean"
  assert t.input_schema.required == None
}

pub fn tool_builder_enum_param_test() {
  let t =
    tool_builder("get_weather")
    |> add_enum_param(
      "unit",
      "Temperature unit",
      ["celsius", "fahrenheit"],
      False,
    )
    |> build

  let assert Some(props) = t.input_schema.properties
  let assert [#("unit", prop)] = props
  assert prop.property_type == "string"
  assert prop.enum_values == Some(["celsius", "fahrenheit"])
}

pub fn tool_builder_string_array_param_test() {
  let t =
    tool_builder("search")
    |> add_string_array_param("keywords", "Search keywords", "A keyword", True)
    |> build

  let assert Some(props) = t.input_schema.properties
  let assert [#("keywords", prop)] = props
  assert prop.property_type == "array"
  assert prop.items != None
}

pub fn tool_builder_object_param_test() {
  let nested = [#("street", property("string")), #("city", property("string"))]
  let t =
    tool_builder("set_address")
    |> add_object_param(
      "address",
      "Address object",
      nested,
      ["street", "city"],
      True,
    )
    |> build

  let assert Some(props) = t.input_schema.properties
  let assert [#("address", prop)] = props
  assert prop.property_type == "object"
  assert prop.properties != None
}

pub fn tool_builder_multiple_params_test() {
  let t =
    tool_builder("get_weather")
    |> builder_with_description("Get weather for a location")
    |> add_string_param("location", "City name", True)
    |> add_enum_param(
      "unit",
      "Temperature unit",
      ["celsius", "fahrenheit"],
      False,
    )
    |> build

  let assert Some(props) = t.input_schema.properties
  assert list.length(props) == 2
  assert t.input_schema.required == Some(["location"])
}

pub fn tool_builder_to_json_test() {
  let t =
    tool_builder("get_weather")
    |> builder_with_description("Get weather")
    |> add_string_param("location", "City name", True)
    |> build

  let json_str = tool_to_json_string(t)
  assert string.contains(json_str, "\"name\":\"get_weather\"")
  assert string.contains(json_str, "\"description\":\"Get weather\"")
  assert string.contains(json_str, "\"location\"")
  assert string.contains(json_str, "\"required\"")
}

pub fn tool_builder_validated_success_test() {
  let result =
    tool_builder("valid_name")
    |> build_validated

  // Should succeed - not an error
  case result {
    Ok(_) -> Nil
    Error(_) -> panic as "Expected Ok but got Error"
  }
}

pub fn tool_builder_validated_empty_name_test() {
  let result =
    tool_builder("")
    |> build_validated

  assert result == Error(InvalidToolName(EmptyToolName))
}

// =============================================================================
// Opaque Type Tests (Issue #11)
// =============================================================================

import anthropic/types/tool.{
  InvalidToolNameCharacters, ToolNameTooLong, tool_name,
  tool_name_error_to_string,
} as tool_module

pub fn tool_name_valid_test() {
  // Valid tool names
  let assert Ok(name) = tool_name("get_weather")
  assert tool_name_to_string(name) == "get_weather"

  let assert Ok(name2) = tool_name("my-tool_123")
  assert tool_name_to_string(name2) == "my-tool_123"
}

pub fn tool_name_empty_error_test() {
  let result = tool_name("")
  assert result == Error(EmptyToolName)
}

pub fn tool_name_invalid_chars_error_test() {
  let result = tool_name("has spaces")
  let assert Error(InvalidToolNameCharacters(_)) = result
}

pub fn tool_name_too_long_error_test() {
  // Create a name with 65 characters (1 over the limit)
  let long_name =
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let result = tool_name(long_name)
  let assert Error(ToolNameTooLong(_, length)) = result
  assert length == 65
}

pub fn tool_name_error_to_string_test() {
  let empty_msg = tool_name_error_to_string(EmptyToolName)
  assert string.contains(empty_msg, "empty")

  let invalid_msg = tool_name_error_to_string(InvalidToolNameCharacters("bad"))
  assert string.contains(invalid_msg, "invalid")
  assert string.contains(invalid_msg, "bad")

  let long_msg = tool_name_error_to_string(ToolNameTooLong("x", 100))
  assert string.contains(long_msg, "too long")
}

import anthropic/config.{
  EmptyApiKey, api_key, api_key_error_to_string, api_key_unchecked,
} as config_module

pub fn api_key_valid_test() {
  let assert Ok(key) = api_key("sk-ant-test")
  assert api_key_to_string(key) == "sk-ant-test"
}

pub fn api_key_empty_error_test() {
  let result = api_key("")
  assert result == Error(EmptyApiKey)
}

pub fn api_key_whitespace_only_error_test() {
  let result = api_key("   ")
  assert result == Error(EmptyApiKey)
}

pub fn api_key_trimmed_test() {
  let assert Ok(key) = api_key("  sk-ant-test  ")
  assert api_key_to_string(key) == "sk-ant-test"
}

pub fn api_key_unchecked_test() {
  let key = api_key_unchecked("my-key")
  assert api_key_to_string(key) == "my-key"
}

pub fn api_key_error_to_string_test() {
  let msg = api_key_error_to_string(EmptyApiKey)
  assert string.contains(msg, "empty")
}

// =============================================================================
// Retry Logic Tests
// =============================================================================

pub fn retry_default_config_test() {
  let config = default_retry_config()
  assert config.max_retries == 3
  assert config.base_delay_ms == 1000
  assert config.max_delay_ms == 60_000
  assert config.backoff_multiplier == 2.0
}

pub fn retry_aggressive_config_test() {
  let config = aggressive_retry_config()
  assert config.max_retries == 5
  assert config.base_delay_ms == 500
}

pub fn retry_no_retry_config_test() {
  let config = no_retry_config()
  assert config.max_retries == 0
}

pub fn retry_config_with_max_retries_test() {
  let config =
    default_retry_config()
    |> retry_module.with_max_retries(10)
  assert config.max_retries == 10
}

pub fn retry_config_with_base_delay_test() {
  let config =
    default_retry_config()
    |> with_base_delay_ms(2000)
  assert config.base_delay_ms == 2000
}

pub fn retry_config_with_max_delay_test() {
  let config =
    default_retry_config()
    |> with_max_delay_ms(60_000)
  assert config.max_delay_ms == 60_000
}

pub fn retry_config_with_jitter_test() {
  let config =
    default_retry_config()
    |> with_jitter_factor(0.5)
  assert config.jitter_factor == 0.5
}

pub fn retry_config_with_backoff_test() {
  let config =
    default_retry_config()
    |> with_backoff_multiplier(3.0)
  assert config.backoff_multiplier == 3.0
}

pub fn retry_calculate_delay_test() {
  let config =
    RetryConfig(
      max_retries: 3,
      base_delay_ms: 1000,
      max_delay_ms: 30_000,
      jitter_factor: 0.0,
      backoff_multiplier: 2.0,
    )
  // First retry: 1000ms
  assert calculate_delay(config, 0) == 1000
  // Second retry: 2000ms
  assert calculate_delay(config, 1) == 2000
  // Third retry: 4000ms
  assert calculate_delay(config, 2) == 4000
}

pub fn retry_calculate_delay_capped_test() {
  let config =
    RetryConfig(
      max_retries: 10,
      base_delay_ms: 1000,
      max_delay_ms: 5000,
      jitter_factor: 0.0,
      backoff_multiplier: 2.0,
    )
  // Fifth retry would be 16000ms but capped at 5000ms
  assert calculate_delay(config, 4) == 5000
}

pub fn retry_is_retryable_rate_limit_test() {
  let err = rate_limit_error("Rate limited")
  assert is_retryable(err) == True
}

pub fn retry_is_retryable_overloaded_test() {
  let err = overloaded_error("Overloaded")
  assert is_retryable(err) == True
}

pub fn retry_is_retryable_internal_test() {
  let err = internal_api_error("Internal error")
  assert is_retryable(err) == True
}

pub fn retry_is_retryable_timeout_test() {
  let err = timeout_error(30_000)
  assert is_retryable(err) == True
}

pub fn retry_is_retryable_network_test() {
  let err = network_error("Connection failed")
  assert is_retryable(err) == True
}

pub fn retry_is_not_retryable_auth_test() {
  let err = authentication_error("Invalid API key")
  assert is_retryable(err) == False
}

pub fn retry_is_not_retryable_invalid_request_test() {
  let err = invalid_request_error("Bad request")
  assert is_retryable(err) == False
}

// =============================================================================
// Validation Tests
// =============================================================================

pub fn validation_field_to_string_test() {
  assert field_to_string(MessagesField) == "messages"
  assert field_to_string(ModelField) == "model"
  assert field_to_string(MaxTokensField) == "max_tokens"
  assert field_to_string(TemperatureField) == "temperature"
  assert field_to_string(TopPField) == "top_p"
  assert field_to_string(TopKField) == "top_k"
  assert field_to_string(SystemField) == "system"
  assert field_to_string(StopSequencesField) == "stop_sequences"
  assert field_to_string(ToolsField) == "tools"
}

pub fn validation_error_constructor_test() {
  let err = validation_error(MessagesField, "messages cannot be empty")
  assert err.field == MessagesField
  assert err.message == "messages cannot be empty"
  assert err.value == None
}

pub fn validation_error_with_value_constructor_test() {
  let err =
    validation_error_with_value(
      MaxTokensField,
      "max_tokens must be positive",
      "-1",
    )
  assert err.field == MaxTokensField
  assert err.message == "max_tokens must be positive"
  assert err.value == Some("-1")
}

pub fn validation_error_to_string_test() {
  let err = validation_error(MessagesField, "messages cannot be empty")
  let result = validation_module.error_to_string(err)
  assert result == "messages: messages cannot be empty"
}

pub fn validation_error_to_string_with_value_test() {
  let err =
    validation_error_with_value(
      MaxTokensField,
      "max_tokens must be positive",
      "-1",
    )
  let result = validation_module.error_to_string(err)
  assert result == "max_tokens: max_tokens must be positive (got: -1)"
}

pub fn validation_errors_to_string_test() {
  let errors = [
    validation_error(MessagesField, "messages cannot be empty"),
    validation_error(ModelField, "model name cannot be empty"),
  ]
  let result = errors_to_string(errors)
  assert string.contains(result, "messages")
  assert string.contains(result, "model")
}

pub fn validate_messages_empty_test() {
  let result = validate_messages([])
  assert result != Ok(Nil)
}

pub fn validate_messages_valid_test() {
  let messages = [user_message("Hello")]
  let result = validate_messages(messages)
  assert result == Ok(Nil)
}

pub fn validate_messages_alternation_test() {
  let messages = [
    user_message("Hello"),
    assistant_message("Hi there!"),
    user_message("How are you?"),
  ]
  let result = validate_messages(messages)
  assert result == Ok(Nil)
}

pub fn validate_messages_wrong_start_test() {
  // Starting with assistant message should fail
  let messages = [assistant_message("Hi")]
  let result = validate_messages(messages)
  assert result != Ok(Nil)
}

pub fn validate_model_empty_test() {
  let result = validate_model("")
  assert result != Ok(Nil)
}

pub fn validate_model_valid_test() {
  let result = validate_model("claude-sonnet-4-20250514")
  assert result == Ok(Nil)
}

pub fn validate_model_with_special_chars_test() {
  let result = validate_model("claude-3.5-sonnet-20241022")
  assert result == Ok(Nil)
}

pub fn validate_max_tokens_valid_test() {
  let result = validate_max_tokens(1024, "claude-sonnet-4-20250514")
  assert result == Ok(Nil)
}

pub fn validate_max_tokens_zero_test() {
  let result = validate_max_tokens(0, "claude-sonnet-4-20250514")
  assert result != Ok(Nil)
}

pub fn validate_max_tokens_negative_test() {
  let result = validate_max_tokens(-1, "claude-sonnet-4-20250514")
  assert result != Ok(Nil)
}

pub fn validate_temperature_valid_test() {
  let result = validate_temperature(Some(0.7))
  assert result == Ok(Nil)
}

pub fn validate_temperature_none_test() {
  let result = validate_temperature(None)
  assert result == Ok(Nil)
}

pub fn validate_temperature_zero_test() {
  let result = validate_temperature(Some(0.0))
  assert result == Ok(Nil)
}

pub fn validate_temperature_one_test() {
  let result = validate_temperature(Some(1.0))
  assert result == Ok(Nil)
}

pub fn validate_temperature_out_of_range_test() {
  let result = validate_temperature(Some(1.5))
  assert result != Ok(Nil)
}

pub fn validate_temperature_negative_test() {
  let result = validate_temperature(Some(-0.5))
  assert result != Ok(Nil)
}

pub fn validate_top_p_valid_test() {
  let result = validate_top_p(Some(0.9))
  assert result == Ok(Nil)
}

pub fn validate_top_p_none_test() {
  let result = validate_top_p(None)
  assert result == Ok(Nil)
}

pub fn validate_top_p_out_of_range_test() {
  let result = validate_top_p(Some(2.0))
  assert result != Ok(Nil)
}

pub fn validate_top_k_valid_test() {
  let result = validate_top_k(Some(40))
  assert result == Ok(Nil)
}

pub fn validate_top_k_none_test() {
  let result = validate_top_k(None)
  assert result == Ok(Nil)
}

pub fn validate_top_k_zero_test() {
  let result = validate_top_k(Some(0))
  assert result != Ok(Nil)
}

pub fn validate_top_k_negative_test() {
  let result = validate_top_k(Some(-1))
  assert result != Ok(Nil)
}

pub fn validate_system_valid_test() {
  let result = validate_system(Some("You are a helpful assistant."))
  assert result == Ok(Nil)
}

pub fn validate_system_none_test() {
  let result = validate_system(None)
  assert result == Ok(Nil)
}

pub fn validate_system_empty_test() {
  let result = validate_system(Some(""))
  assert result != Ok(Nil)
}

pub fn validate_system_whitespace_test() {
  let result = validate_system(Some("   "))
  assert result != Ok(Nil)
}

pub fn validate_stop_sequences_valid_test() {
  let result = validate_stop_sequences(Some(["END", "STOP"]))
  assert result == Ok(Nil)
}

pub fn validate_stop_sequences_none_test() {
  let result = validate_stop_sequences(None)
  assert result == Ok(Nil)
}

pub fn validate_stop_sequences_empty_item_test() {
  let result = validate_stop_sequences(Some(["END", ""]))
  assert result != Ok(Nil)
}

pub fn validate_tools_valid_test() {
  let tools = [
    Tool(
      name: tool_name_unchecked("get_weather"),
      description: None,
      input_schema: empty_input_schema(),
    ),
  ]
  let result = validate_tools(Some(tools))
  assert result == Ok(Nil)
}

pub fn validate_tools_none_test() {
  let result = validate_tools(None)
  assert result == Ok(Nil)
}

// Note: validate_tools_empty_name_test was removed because ToolName is now
// an opaque type that validates at construction. Invalid tool names cannot
// be created through the type system. The test for empty names is now
// in tool_builder_validated_empty_name_test and tool_name_error_test.

pub fn validate_request_valid_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
  let result = validate_request(request)
  assert result == Ok(Nil)
}

pub fn validate_request_invalid_test() {
  let request = create_request("", [], 0)
  let result = validate_request(request)
  assert result != Ok(Nil)
}

pub fn is_valid_true_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
  assert is_valid(request) == True
}

pub fn is_valid_false_test() {
  let request = create_request("", [], 0)
  assert is_valid(request) == False
}

pub fn validate_or_error_success_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
  let result = validate_or_error(request)
  assert result == Ok(request)
}

pub fn validate_or_error_failure_test() {
  let request = create_request("", [], 0)
  let result = validate_or_error(request)
  case result {
    Ok(_) -> Nil
    Error(_) -> Nil
  }
  // Just verify we get an Error (it would be Ok for a valid request)
  assert result != Ok(request)
}

pub fn validate_content_blocks_valid_test() {
  let blocks = [TextBlock(text: "Hello")]
  let result = validate_content_blocks(blocks)
  assert result == Ok(Nil)
}

pub fn validate_content_blocks_empty_test() {
  let result = validate_content_blocks([])
  assert result != Ok(Nil)
}

pub fn validate_content_blocks_empty_text_test() {
  let blocks = [TextBlock(text: "")]
  let result = validate_content_blocks(blocks)
  assert result != Ok(Nil)
}

pub fn get_model_limits_opus_test() {
  let limits = get_model_limits("claude-3-opus-20240229")
  assert limits.max_tokens == 4096
  assert limits.context_window == 200_000
}

pub fn get_model_limits_sonnet_test() {
  let limits = get_model_limits("claude-sonnet-4-20250514")
  assert limits.max_tokens == 8192
}

pub fn get_model_limits_haiku_test() {
  let limits = get_model_limits("claude-3-5-haiku-20241022")
  assert limits.max_tokens == 8192
}

// =============================================================================
// Hooks Tests
// =============================================================================

pub fn hooks_default_test() {
  let h = default_hooks()
  assert h.on_request_start == None
  assert h.on_request_end == None
  assert h.on_retry == None
  assert h.on_stream_event == None
}

pub fn hooks_no_hooks_test() {
  let h = no_hooks()
  assert h.on_request_start == None
  assert h.on_request_end == None
}

pub fn hooks_has_hooks_false_test() {
  let h = default_hooks()
  assert has_hooks(h) == False
}

pub fn hooks_has_hooks_true_test() {
  let h =
    default_hooks()
    |> with_on_request_start(fn(_) { Nil })
  assert has_hooks(h) == True
}

pub fn hooks_with_on_request_start_test() {
  let h =
    default_hooks()
    |> with_on_request_start(fn(_) { Nil })
  assert h.on_request_start != None
}

pub fn hooks_with_on_request_end_test() {
  let h =
    default_hooks()
    |> with_on_request_end(fn(_) { Nil })
  assert h.on_request_end != None
}

pub fn hooks_with_on_retry_test() {
  let h =
    default_hooks()
    |> with_on_retry(fn(_) { Nil })
  assert h.on_retry != None
}

pub fn hooks_with_on_stream_event_test() {
  let h =
    default_hooks()
    |> with_on_stream_event(fn(_) { Nil })
  assert h.on_stream_event != None
}

pub fn hooks_combine_both_none_test() {
  let first = default_hooks()
  let second = default_hooks()
  let combined = combine_hooks(first, second)
  assert combined.on_request_start == None
}

pub fn hooks_combine_first_some_test() {
  let first = default_hooks() |> with_on_request_start(fn(_) { Nil })
  let second = default_hooks()
  let combined = combine_hooks(first, second)
  assert combined.on_request_start != None
}

pub fn hooks_combine_second_some_test() {
  let first = default_hooks()
  let second = default_hooks() |> with_on_request_start(fn(_) { Nil })
  let combined = combine_hooks(first, second)
  assert combined.on_request_start != None
}

pub fn hooks_combine_both_some_test() {
  let first = default_hooks() |> with_on_request_start(fn(_) { Nil })
  let second = default_hooks() |> with_on_request_start(fn(_) { Nil })
  let combined = combine_hooks(first, second)
  assert combined.on_request_start != None
}

pub fn hooks_emit_request_start_with_callback_test() {
  // This tests that emit doesn't crash when callback is set
  let h = default_hooks() |> with_on_request_start(fn(_) { Nil })
  let event =
    RequestStartEvent(
      endpoint: "/v1/messages",
      request: hooks_module.RequestSummary(
        model: "claude-sonnet-4-20250514",
        message_count: 1,
        max_tokens: 1024,
        stream: False,
        tool_count: 0,
        has_system: False,
      ),
      timestamp_ms: 0,
      request_id: "req_123",
    )
  emit_request_start(h, event)
  // If we get here, it didn't crash
  assert True
}

pub fn hooks_emit_request_start_without_callback_test() {
  let h = default_hooks()
  let event =
    RequestStartEvent(
      endpoint: "/v1/messages",
      request: hooks_module.RequestSummary(
        model: "claude-sonnet-4-20250514",
        message_count: 1,
        max_tokens: 1024,
        stream: False,
        tool_count: 0,
        has_system: False,
      ),
      timestamp_ms: 0,
      request_id: "req_123",
    )
  emit_request_start(h, event)
  assert True
}

pub fn hooks_emit_request_end_test() {
  let h = default_hooks() |> with_on_request_end(fn(_) { Nil })
  let event =
    RequestEndEvent(
      endpoint: "/v1/messages",
      duration_ms: 100,
      success: True,
      response: None,
      error: None,
      request_id: "req_123",
      retry_count: 0,
    )
  emit_request_end(h, event)
  assert True
}

pub fn hooks_emit_retry_test() {
  let h = default_hooks() |> with_on_retry(fn(_) { Nil })
  let event =
    RetryEvent(
      endpoint: "/v1/messages",
      attempt: 1,
      max_attempts: 3,
      delay_ms: 1000,
      error: rate_limit_error("Rate limited"),
      request_id: "req_123",
    )
  emit_retry(h, event)
  assert True
}

pub fn hooks_emit_stream_event_test() {
  let h = default_hooks() |> with_on_stream_event(fn(_) { Nil })
  let event =
    StreamEvent(
      event_type: StreamOpened,
      request_id: "req_123",
      timestamp_ms: 0,
    )
  emit_stream_event(h, event)
  assert True
}

pub fn hooks_generate_request_id_test() {
  let id1 = generate_request_id()
  let id2 = generate_request_id()
  // IDs should start with "req_"
  assert string.starts_with(id1, "req_")
  assert string.starts_with(id2, "req_")
}

pub fn hooks_summarize_request_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
  let summary = summarize_request(request)
  assert summary.model == "claude-sonnet-4-20250514"
  assert summary.message_count == 1
  assert summary.max_tokens == 1024
  assert summary.stream == False
  assert summary.tool_count == 0
  assert summary.has_system == False
}

pub fn hooks_summarize_request_with_options_test() {
  let request =
    create_request(
      "claude-sonnet-4-20250514",
      [user_message("Hello"), assistant_message("Hi"), user_message("Bye")],
      2048,
    )
    |> with_stream(True)
    |> with_system("You are helpful")
    |> with_tools([
      Tool(
        name: tool_name_unchecked("test_tool"),
        description: None,
        input_schema: empty_input_schema(),
      ),
    ])
  let summary = summarize_request(request)
  assert summary.message_count == 3
  assert summary.max_tokens == 2048
  assert summary.stream == True
  assert summary.tool_count == 1
  assert summary.has_system == True
}

pub fn hooks_simple_logging_hooks_test() {
  let h = simple_logging_hooks()
  // Should have request start, end, and retry hooks
  assert h.on_request_start != None
  assert h.on_request_end != None
  assert h.on_retry != None
}

pub fn hooks_metrics_hooks_test() {
  let h = metrics_hooks(fn(_, _) { Nil })
  // Should have request end hook for metrics
  assert h.on_request_end != None
}

pub fn hooks_stream_event_type_test() {
  // Test stream event types construction
  let opened = StreamOpened
  let msg_start = MessageStart
  let block_start = ContentBlockStart(index: 0)
  let block_delta = ContentBlockDelta(index: 0, delta_type: "text_delta")
  let block_stop = ContentBlockStop(index: 0)
  let msg_delta = MessageDelta
  let msg_stop = MessageStop
  let closed = StreamClosed
  let err = StreamError(error: "connection lost")

  // Just verify they can be constructed and have expected values
  assert opened == StreamOpened
  assert msg_start == MessageStart
  assert block_start == ContentBlockStart(index: 0)
  assert block_delta == ContentBlockDelta(index: 0, delta_type: "text_delta")
  assert block_stop == ContentBlockStop(index: 0)
  assert msg_delta == MessageDelta
  assert msg_stop == MessageStop
  assert closed == StreamClosed
  assert err == StreamError(error: "connection lost")
}

// =============================================================================
// Sans-IO HTTP Module Tests
// =============================================================================

import anthropic/http.{
  Delete, Get, HttpRequest, HttpResponse, Patch, Post, Put,
  build_messages_request, build_streaming_request, check_status,
  method_to_string, parse_messages_response, parse_response_body,
  validate_request as http_validate_request,
}

// -----------------------------------------------------------------------------
// HTTP Method Tests
// -----------------------------------------------------------------------------

pub fn http_method_to_string_get_test() {
  assert method_to_string(Get) == "GET"
}

pub fn http_method_to_string_post_test() {
  assert method_to_string(Post) == "POST"
}

pub fn http_method_to_string_put_test() {
  assert method_to_string(Put) == "PUT"
}

pub fn http_method_to_string_delete_test() {
  assert method_to_string(Delete) == "DELETE"
}

pub fn http_method_to_string_patch_test() {
  assert method_to_string(Patch) == "PATCH"
}

// -----------------------------------------------------------------------------
// HTTP Request Building Tests
// -----------------------------------------------------------------------------

pub fn http_build_messages_request_basic_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)

  let http_req =
    build_messages_request(
      "sk-ant-test-key",
      "https://api.anthropic.com",
      request,
    )

  assert http_req.method == Post
  assert http_req.url == "https://api.anthropic.com/v1/messages"
  assert string.contains(
    http_req.body,
    "\"model\":\"claude-sonnet-4-20250514\"",
  )
  assert string.contains(http_req.body, "\"max_tokens\":1024")
}

pub fn http_build_messages_request_headers_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)

  let http_req =
    build_messages_request(
      "sk-ant-test-key",
      "https://api.anthropic.com",
      request,
    )

  // Check required headers are present
  assert list.any(http_req.headers, fn(h) {
    h.0 == "content-type" && h.1 == "application/json"
  })
  assert list.any(http_req.headers, fn(h) {
    h.0 == "x-api-key" && h.1 == "sk-ant-test-key"
  })
  assert list.any(http_req.headers, fn(h) {
    h.0 == "anthropic-version" && h.1 == "2023-06-01"
  })
}

pub fn http_build_messages_request_custom_base_url_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)

  let http_req =
    build_messages_request("key", "https://custom.proxy.com", request)

  assert http_req.url == "https://custom.proxy.com/v1/messages"
}

pub fn http_build_messages_request_with_system_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_system("You are a helpful assistant")

  let http_req =
    build_messages_request("key", "https://api.anthropic.com", request)

  assert string.contains(
    http_req.body,
    "\"system\":\"You are a helpful assistant\"",
  )
}

pub fn http_build_messages_request_with_temperature_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_temperature(0.7)

  let http_req =
    build_messages_request("key", "https://api.anthropic.com", request)

  assert string.contains(http_req.body, "\"temperature\":0.7")
}

pub fn http_build_streaming_request_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)

  let http_req =
    build_streaming_request("sk-ant-key", "https://api.anthropic.com", request)

  // Should have stream: true in body
  assert string.contains(http_req.body, "\"stream\":true")
  // Should have Accept header for SSE
  assert list.any(http_req.headers, fn(h) {
    h.0 == "accept" && h.1 == "text/event-stream"
  })
}

pub fn http_build_streaming_request_preserves_other_options_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 2048)
    |> with_system("Be concise")
    |> with_temperature(0.5)

  let http_req =
    build_streaming_request("key", "https://api.anthropic.com", request)

  assert string.contains(http_req.body, "\"max_tokens\":2048")
  assert string.contains(http_req.body, "\"system\":\"Be concise\"")
  assert string.contains(http_req.body, "\"temperature\":0.5")
  assert string.contains(http_req.body, "\"stream\":true")
}

// -----------------------------------------------------------------------------
// HTTP Response Parsing Tests
// -----------------------------------------------------------------------------

pub fn http_parse_messages_response_success_test() {
  let response_body =
    "{\"id\":\"msg_123\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Hello there!\"}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"end_turn\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}"

  let http_response =
    HttpResponse(status: 200, headers: [], body: response_body)

  case parse_messages_response(http_response) {
    Ok(response) -> {
      assert response.id == "msg_123"
      assert response.model == "claude-sonnet-4-20250514"
      assert response.role == Assistant
      assert response.stop_reason == Some(EndTurn)
      assert response.usage.input_tokens == 10
      assert response.usage.output_tokens == 5
      assert response_text(response) == "Hello there!"
    }
    Error(_) -> panic as "Expected successful parse"
  }
}

pub fn http_parse_messages_response_with_tool_use_test() {
  let response_body =
    "{\"id\":\"msg_456\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_123\",\"name\":\"get_weather\",\"input\":{\"location\":\"London\"}}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"tool_use\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":20,\"output_tokens\":15}}"

  let http_response =
    HttpResponse(status: 200, headers: [], body: response_body)

  case parse_messages_response(http_response) {
    Ok(response) -> {
      assert response.stop_reason == Some(ToolUse)
      assert response_has_tool_use(response) == True
      let tool_uses = response_get_tool_uses(response)
      assert list.length(tool_uses) == 1
      case list.first(tool_uses) {
        Ok(ToolUseBlock(id, name, input)) -> {
          assert id == "toolu_123"
          assert name == "get_weather"
          assert string.contains(input, "London")
        }
        _ -> panic as "Expected ToolUseBlock"
      }
    }
    Error(_) -> panic as "Expected successful parse"
  }
}

pub fn http_parse_messages_response_max_tokens_stop_test() {
  let response_body =
    "{\"id\":\"msg_789\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"This is truncated...\"}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"max_tokens\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":5,\"output_tokens\":100}}"

  let http_response =
    HttpResponse(status: 200, headers: [], body: response_body)

  case parse_messages_response(http_response) {
    Ok(response) -> {
      assert response.stop_reason == Some(MaxTokens)
    }
    Error(_) -> panic as "Expected successful parse"
  }
}

pub fn http_parse_messages_response_stop_sequence_test() {
  let response_body =
    "{\"id\":\"msg_abc\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"stop_sequence\",\"stop_sequence\":\"END\",\"usage\":{\"input_tokens\":5,\"output_tokens\":10}}"

  let http_response =
    HttpResponse(status: 200, headers: [], body: response_body)

  case parse_messages_response(http_response) {
    Ok(response) -> {
      assert response.stop_reason == Some(StopSequence)
      assert response.stop_sequence == Some("END")
    }
    Error(_) -> panic as "Expected successful parse"
  }
}

pub fn http_parse_messages_response_multiple_content_blocks_test() {
  let response_body =
    "{\"id\":\"msg_multi\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"First block\"},{\"type\":\"text\",\"text\":\" and second block\"}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"end_turn\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":10,\"output_tokens\":20}}"

  let http_response =
    HttpResponse(status: 200, headers: [], body: response_body)

  case parse_messages_response(http_response) {
    Ok(response) -> {
      assert list.length(response.content) == 2
      assert response_text(response) == "First block and second block"
    }
    Error(_) -> panic as "Expected successful parse"
  }
}

// -----------------------------------------------------------------------------
// HTTP Status Code Handling Tests
// -----------------------------------------------------------------------------

pub fn http_check_status_200_success_test() {
  let response = HttpResponse(status: 200, headers: [], body: "test body")
  case check_status(response) {
    Ok(body) -> {
      assert body == "test body"
    }
    Error(_) -> panic as "Expected success"
  }
}

pub fn http_check_status_400_invalid_request_test() {
  let error_body =
    "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Invalid model\"}}"
  let response = HttpResponse(status: 400, headers: [], body: error_body)

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_retryable(err) == False
      assert error_category(err) == "api"
      assert get_status_code(err) == Some(400)
    }
  }
}

pub fn http_check_status_401_authentication_test() {
  let error_body =
    "{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"Invalid API key\"}}"
  let response = HttpResponse(status: 401, headers: [], body: error_body)

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_authentication_error(err) == True
      assert is_retryable(err) == False
      assert get_status_code(err) == Some(401)
    }
  }
}

pub fn http_check_status_403_permission_test() {
  let error_body =
    "{\"type\":\"error\",\"error\":{\"type\":\"permission_error\",\"message\":\"Access denied\"}}"
  let response = HttpResponse(status: 403, headers: [], body: error_body)

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_retryable(err) == False
      assert get_status_code(err) == Some(403)
    }
  }
}

pub fn http_check_status_404_not_found_test() {
  let error_body =
    "{\"type\":\"error\",\"error\":{\"type\":\"not_found_error\",\"message\":\"Resource not found\"}}"
  let response = HttpResponse(status: 404, headers: [], body: error_body)

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_retryable(err) == False
      assert get_status_code(err) == Some(404)
    }
  }
}

pub fn http_check_status_429_rate_limit_test() {
  let error_body =
    "{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"Too many requests\"}}"
  let response = HttpResponse(status: 429, headers: [], body: error_body)

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_rate_limit_error(err) == True
      assert is_retryable(err) == True
      assert get_status_code(err) == Some(429)
    }
  }
}

pub fn http_check_status_500_internal_error_test() {
  let error_body =
    "{\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"Internal server error\"}}"
  let response = HttpResponse(status: 500, headers: [], body: error_body)

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_retryable(err) == True
      assert get_status_code(err) == Some(500)
    }
  }
}

pub fn http_check_status_529_overloaded_test() {
  let error_body =
    "{\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"API is overloaded\"}}"
  let response = HttpResponse(status: 529, headers: [], body: error_body)

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_overloaded_error(err) == True
      assert is_retryable(err) == True
      assert get_status_code(err) == Some(529)
    }
  }
}

pub fn http_check_status_other_4xx_test() {
  let error_body =
    "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Some 4xx error\"}}"
  let response = HttpResponse(status: 418, headers: [], body: error_body)

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_retryable(err) == False
      assert get_status_code(err) == Some(418)
    }
  }
}

pub fn http_check_status_other_5xx_test() {
  let error_body =
    "{\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"Some 5xx error\"}}"
  let response = HttpResponse(status: 503, headers: [], body: error_body)

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_retryable(err) == True
      assert get_status_code(err) == Some(503)
    }
  }
}

pub fn http_check_status_malformed_error_body_test() {
  // When error body can't be parsed, should still return proper error
  let response = HttpResponse(status: 400, headers: [], body: "not json")

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert get_status_code(err) == Some(400)
    }
  }
}

pub fn http_check_status_unexpected_status_test() {
  let response = HttpResponse(status: 102, headers: [], body: "processing")

  case check_status(response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert error_category(err) == "http"
    }
  }
}

// -----------------------------------------------------------------------------
// HTTP Response Body Parsing Tests
// -----------------------------------------------------------------------------

pub fn http_parse_response_body_valid_json_test() {
  let body =
    "{\"id\":\"msg_test\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Hi\"}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"end_turn\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}"

  case parse_response_body(body) {
    Ok(response) -> {
      assert response.id == "msg_test"
      assert response_text(response) == "Hi"
    }
    Error(_) -> panic as "Expected successful parse"
  }
}

pub fn http_parse_response_body_invalid_json_test() {
  let body = "not valid json"

  case parse_response_body(body) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert error_category(err) == "json"
    }
  }
}

pub fn http_parse_response_body_missing_fields_test() {
  let body = "{\"id\":\"msg_test\"}"

  case parse_response_body(body) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert error_category(err) == "json"
    }
  }
}

// -----------------------------------------------------------------------------
// HTTP Request Validation Tests
// -----------------------------------------------------------------------------

pub fn http_validate_request_valid_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 1024)

  case http_validate_request(request) {
    Ok(_) -> {
      assert True
    }
    Error(_) -> panic as "Expected valid request"
  }
}

pub fn http_validate_request_empty_messages_test() {
  let request = create_request("claude-sonnet-4-20250514", [], 1024)

  case http_validate_request(request) {
    Ok(_) -> panic as "Expected validation error"
    Error(err) -> {
      assert string.contains(error_to_string(err), "messages")
    }
  }
}

pub fn http_validate_request_empty_model_test() {
  let request = create_request("", [user_message("Hello")], 1024)

  case http_validate_request(request) {
    Ok(_) -> panic as "Expected validation error"
    Error(err) -> {
      assert string.contains(error_to_string(err), "model")
    }
  }
}

pub fn http_validate_request_whitespace_model_test() {
  let request = create_request("   ", [user_message("Hello")], 1024)

  case http_validate_request(request) {
    Ok(_) -> panic as "Expected validation error"
    Error(err) -> {
      assert string.contains(error_to_string(err), "model")
    }
  }
}

pub fn http_validate_request_zero_max_tokens_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], 0)

  case http_validate_request(request) {
    Ok(_) -> panic as "Expected validation error"
    Error(err) -> {
      assert string.contains(error_to_string(err), "max_tokens")
    }
  }
}

pub fn http_validate_request_negative_max_tokens_test() {
  let request =
    create_request("claude-sonnet-4-20250514", [user_message("Hello")], -100)

  case http_validate_request(request) {
    Ok(_) -> panic as "Expected validation error"
    Error(err) -> {
      assert string.contains(error_to_string(err), "max_tokens")
    }
  }
}

// -----------------------------------------------------------------------------
// HTTP Type Construction Tests
// -----------------------------------------------------------------------------

pub fn http_request_type_construction_test() {
  let request =
    HttpRequest(
      method: Post,
      url: "https://example.com/api",
      headers: [#("Authorization", "Bearer token")],
      body: "{\"test\": true}",
    )

  assert request.method == Post
  assert request.url == "https://example.com/api"
  assert list.length(request.headers) == 1
  assert request.body == "{\"test\": true}"
}

pub fn http_response_type_construction_test() {
  let response =
    HttpResponse(
      status: 201,
      headers: [#("Content-Type", "application/json")],
      body: "{\"created\": true}",
    )

  assert response.status == 201
  assert list.length(response.headers) == 1
  assert response.body == "{\"created\": true}"
}

// -----------------------------------------------------------------------------
// HTTP Constants Tests
// -----------------------------------------------------------------------------

pub fn http_api_version_constant_test() {
  assert http.api_version == "2023-06-01"
}

pub fn http_messages_endpoint_constant_test() {
  assert http.messages_endpoint == "/v1/messages"
}

pub fn http_default_base_url_constant_test() {
  assert http.default_base_url == "https://api.anthropic.com"
}

// -----------------------------------------------------------------------------
// HTTP Integration Pattern Tests
// -----------------------------------------------------------------------------

pub fn http_round_trip_pattern_test() {
  // This tests the typical sans-io workflow:
  // 1. Build request
  // 2. (User would send with their HTTP client)
  // 3. Parse response

  // Step 1: Build the request
  let api_request =
    create_request(
      "claude-sonnet-4-20250514",
      [user_message("What is 2+2?")],
      100,
    )
    |> with_temperature(0.0)

  let http_request =
    build_messages_request("test-api-key", http.default_base_url, api_request)

  // Verify request is properly formed
  assert http_request.method == Post
  assert http_request.url == "https://api.anthropic.com/v1/messages"
  assert string.contains(http_request.body, "What is 2+2?")

  // Step 2: Simulate response from HTTP client
  let http_response =
    HttpResponse(
      status: 200,
      headers: [#("content-type", "application/json")],
      body: "{\"id\":\"msg_roundtrip\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"2+2 equals 4.\"}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"end_turn\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":15,\"output_tokens\":8}}",
    )

  // Step 3: Parse response
  case parse_messages_response(http_response) {
    Ok(response) -> {
      assert response.id == "msg_roundtrip"
      assert response_text(response) == "2+2 equals 4."
      assert response.usage.input_tokens == 15
      assert response.usage.output_tokens == 8
    }
    Error(_) -> panic as "Expected successful parse"
  }
}

pub fn http_streaming_round_trip_pattern_test() {
  // Test the streaming request building pattern
  let api_request =
    create_request(
      "claude-sonnet-4-20250514",
      [user_message("Count to 3")],
      100,
    )

  let http_request =
    build_streaming_request("test-api-key", http.default_base_url, api_request)

  // Verify streaming-specific setup
  assert string.contains(http_request.body, "\"stream\":true")
  assert list.any(http_request.headers, fn(h) {
    h.0 == "accept" && h.1 == "text/event-stream"
  })
}

pub fn http_error_handling_pattern_test() {
  // Test error response handling pattern
  let http_response =
    HttpResponse(
      status: 401,
      headers: [],
      body: "{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"Invalid API key provided\"}}",
    )

  case parse_messages_response(http_response) {
    Ok(_) -> panic as "Expected error"
    Error(err) -> {
      assert is_authentication_error(err) == True
      let err_str = error_to_string(err)
      assert string.contains(err_str, "Invalid API key")
    }
  }
}

pub fn http_tool_use_response_pattern_test() {
  // Test tool use response handling
  let http_response =
    HttpResponse(
      status: 200,
      headers: [],
      body: "{\"id\":\"msg_tools\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Let me check the weather.\"},{\"type\":\"tool_use\",\"id\":\"toolu_weather\",\"name\":\"get_weather\",\"input\":{\"city\":\"Paris\",\"units\":\"celsius\"}}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"tool_use\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":50,\"output_tokens\":30}}",
    )

  case parse_messages_response(http_response) {
    Ok(response) -> {
      // Should have both text and tool_use blocks
      assert list.length(response.content) == 2
      assert response_text(response) == "Let me check the weather."
      assert response_has_tool_use(response) == True
      assert response.stop_reason == Some(ToolUse)

      // Verify tool use details
      let tools = response_get_tool_uses(response)
      assert list.length(tools) == 1
      case list.first(tools) {
        Ok(ToolUseBlock(id, name, input)) -> {
          assert id == "toolu_weather"
          assert name == "get_weather"
          assert string.contains(input, "Paris")
          assert string.contains(input, "celsius")
        }
        _ -> panic as "Expected ToolUseBlock"
      }
    }
    Error(_) -> panic as "Expected successful parse"
  }
}

// =============================================================================
// Unified API Tests
// =============================================================================

pub fn api_stream_result_type_test() {
  // Test that StreamResult type works correctly
  let result = ApiStreamResultConstructor(events: [])
  assert result.events == []
}

pub fn api_stream_text_empty_test() {
  // Test stream_text with no events
  let result = ApiStreamResultConstructor(events: [])
  assert stream_text(result) == ""
}

pub fn api_stream_text_with_text_deltas_test() {
  // Test stream_text extracts text from ContentBlockDeltaEventVariant events
  let events = [
    ContentBlockDeltaEventVariant(content_block_delta: ContentBlockDeltaEvent(
      index: 0,
      delta: TextContentDelta(TextDelta(text: "Hello, ")),
    )),
    ContentBlockDeltaEventVariant(content_block_delta: ContentBlockDeltaEvent(
      index: 0,
      delta: TextContentDelta(TextDelta(text: "world!")),
    )),
  ]
  let result = ApiStreamResultConstructor(events: events)
  assert stream_text(result) == "Hello, world!"
}

pub fn api_event_text_with_text_delta_test() {
  // Test event_text extracts text from a text delta event
  let event =
    ContentBlockDeltaEventVariant(content_block_delta: ContentBlockDeltaEvent(
      index: 0,
      delta: TextContentDelta(TextDelta(text: "Hello")),
    ))
  assert event_text(event) == Ok("Hello")
}

pub fn api_event_text_with_non_text_event_test() {
  // Test event_text returns Error for non-text events
  let event = MessageStopEvent
  assert event_text(event) == Error(Nil)
}

pub fn api_stream_complete_with_message_stop_test() {
  // Test api_stream_complete returns True when MessageStopEvent is present
  let result = ApiStreamResultConstructor(events: [MessageStopEvent])
  assert api_stream_complete(result) == True
}

pub fn api_stream_complete_without_message_stop_test() {
  // Test api_stream_complete returns False without MessageStopEvent
  let result = ApiStreamResultConstructor(events: [])
  assert api_stream_complete(result) == False
}

pub fn api_stream_has_error_with_error_event_test() {
  // Test api_stream_has_error returns True when ErrorEvent is present
  let error_event =
    ErrorEvent(error: StreamingErrorConstructor(
      error_type: "overloaded_error",
      message: "Server overloaded",
    ))
  let result = ApiStreamResultConstructor(events: [error_event])
  assert api_stream_has_error(result) == True
}

pub fn api_stream_has_error_without_error_event_test() {
  // Test api_stream_has_error returns False without ErrorEvent
  let result = ApiStreamResultConstructor(events: [MessageStopEvent])
  assert api_stream_has_error(result) == False
}

pub fn api_stream_message_id_test() {
  // Test stream_message_id extracts ID from MessageStartEvent
  let events = [
    MessageStartEvent(message: StreamingMessageStart(
      id: "msg_test123",
      message_type: "message",
      role: Assistant,
      model: "claude-sonnet-4-20250514",
      usage: Usage(input_tokens: 10, output_tokens: 0),
    )),
  ]
  let result = ApiStreamResultConstructor(events: events)
  assert stream_message_id(result) == Ok("msg_test123")
}

pub fn api_stream_message_id_not_found_test() {
  // Test stream_message_id returns Error when no MessageStartEvent
  let result = ApiStreamResultConstructor(events: [MessageStopEvent])
  assert stream_message_id(result) == Error(Nil)
}

pub fn api_stream_model_test() {
  // Test stream_model extracts model from MessageStartEvent
  let events = [
    MessageStartEvent(message: StreamingMessageStart(
      id: "msg_test",
      message_type: "message",
      role: Assistant,
      model: "claude-sonnet-4-20250514",
      usage: Usage(input_tokens: 10, output_tokens: 0),
    )),
  ]
  let result = ApiStreamResultConstructor(events: events)
  assert stream_model(result) == Ok("claude-sonnet-4-20250514")
}

pub fn api_stream_error_type_test() {
  // Test StreamError type variants
  let http_err =
    StreamHttpError(error: NetworkError(reason: "Connection failed"))
  let sse_err = SseParseError(message: "Invalid SSE format")
  let decode_err = EventDecodeError(message: "Invalid JSON")
  let api_err = StreamApiError(status: 500, body: "Internal error")

  // Verify each error type can be constructed and matched
  let _ = case http_err {
    StreamHttpError(_) -> Nil
    _ -> Nil
  }

  let _ = case sse_err {
    SseParseError(msg) -> {
      assert msg == "Invalid SSE format"
    }
    _ -> Nil
  }

  let _ = case decode_err {
    EventDecodeError(msg) -> {
      assert msg == "Invalid JSON"
    }
    _ -> Nil
  }

  case api_err {
    StreamApiError(status: s, body: b) -> {
      assert s == 500
      assert b == "Internal error"
    }
    _ -> Nil
  }
}

pub fn api_chat_alias_test() {
  // Test that chat function exists and properly wraps create_message
  // We can't make real API calls, but we can verify the function signature
  // by testing that validation works the same way
  set_env("ANTHROPIC_API_KEY", "test-api-key")
  let assert Ok(client) = init()

  // Create a request with empty messages (should fail validation)
  let request = create_request("claude-sonnet-4-20250514", [], 1024)

  // Both chat and create_message should fail validation the same way
  let chat_result = chat(client, request)
  let create_result = create_message(client, request)

  // Both should return the same validation error
  assert chat_result == create_result
}

// =============================================================================
// request.new Tests (Issue #22 - Rename API)
// =============================================================================

pub fn request_new_basic_test() {
  // Test that request.new creates a valid request
  let req =
    request_new("claude-sonnet-4-20250514", [user_message("Hello!")], 1024)
  assert req.model == "claude-sonnet-4-20250514"
  assert req.max_tokens == 1024
  assert list.length(req.messages) == 1
}

pub fn request_new_equivalent_to_create_request_test() {
  // Test that request.new and create_request produce identical results
  let new_req =
    request_new("claude-sonnet-4-20250514", [user_message("Test")], 512)
  let old_req =
    create_request("claude-sonnet-4-20250514", [user_message("Test")], 512)
  assert new_req == old_req
}

pub fn request_new_with_builders_test() {
  // Test that request.new works with all builder functions
  let req =
    request_new("claude-sonnet-4-20250514", [user_message("Hello")], 1024)
    |> with_system("You are helpful")
    |> with_temperature(0.7)
    |> with_top_p(0.9)
    |> with_top_k(40)

  assert req.model == "claude-sonnet-4-20250514"
  assert req.system == Some("You are helpful")
  assert req.temperature == Some(0.7)
  assert req.top_p == Some(0.9)
  assert req.top_k == Some(40)
}

pub fn api_chat_with_request_new_test() {
  // Test that api.chat works with request.new
  set_env("ANTHROPIC_API_KEY", "test-api-key")
  let assert Ok(client) = init()

  // Create request using new() instead of create_request()
  let req = request_new("claude-sonnet-4-20250514", [], 1024)

  // chat should fail validation (empty messages)
  let chat_result = chat(client, req)
  case chat_result {
    Error(_) -> Nil
    Ok(_) -> panic as "Expected validation error"
  }
}

// =============================================================================
// RequestOptions Tests
// =============================================================================

pub fn options_creates_default_options_test() {
  let opts = options()
  assert opts.max_tokens == 1024
  assert opts.system == None
  assert opts.temperature == None
  assert opts.top_p == None
  assert opts.top_k == None
  assert opts.stop_sequences == None
  assert opts.stream == None
  assert opts.metadata == None
  assert opts.tools == None
  assert opts.tool_choice == None
}

pub fn opt_max_tokens_test() {
  let opts = options() |> opt_max_tokens(2048)
  assert opts.max_tokens == 2048
}

pub fn opt_system_test() {
  let opts = options() |> opt_system("You are helpful")
  assert opts.system == Some("You are helpful")
}

pub fn opt_temperature_test() {
  let opts = options() |> opt_temperature(0.7)
  assert opts.temperature == Some(0.7)
}

pub fn opt_top_p_test() {
  let opts = options() |> opt_top_p(0.9)
  assert opts.top_p == Some(0.9)
}

pub fn opt_top_k_test() {
  let opts = options() |> opt_top_k(40)
  assert opts.top_k == Some(40)
}

pub fn opt_stop_sequences_test() {
  let opts = options() |> opt_stop_sequences(["stop", "end"])
  assert opts.stop_sequences == Some(["stop", "end"])
}

pub fn opt_stream_test() {
  let opts = options() |> opt_stream(True)
  assert opts.stream == Some(True)
}

pub fn opt_metadata_test() {
  let metadata = Metadata(user_id: Some("user-123"))
  let opts = options() |> opt_metadata(metadata)
  assert opts.metadata == Some(metadata)
}

pub fn opt_user_id_test() {
  let opts = options() |> opt_user_id("user-456")
  assert opts.metadata == Some(Metadata(user_id: Some("user-456")))
}

pub fn opt_tools_test() {
  let tool =
    Tool(
      name: tool_name_unchecked("calculator"),
      description: Some("A calculator"),
      input_schema: empty_input_schema(),
    )
  let opts = options() |> opt_tools([tool])
  assert opts.tools == Some([tool])
}

pub fn opt_tool_choice_test() {
  let opts = options() |> opt_tool_choice(Auto)
  assert opts.tool_choice == Some(Auto)
}

pub fn opt_tools_and_choice_test() {
  let tool =
    Tool(
      name: tool_name_unchecked("search"),
      description: Some("A search tool"),
      input_schema: empty_input_schema(),
    )
  let opts = options() |> opt_tools_and_choice([tool], Any)
  assert opts.tools == Some([tool])
  assert opts.tool_choice == Some(Any)
}

pub fn options_chain_multiple_test() {
  let opts =
    options()
    |> opt_system("Be creative")
    |> opt_temperature(0.9)
    |> opt_top_p(0.95)
    |> opt_max_tokens(4096)

  assert opts.system == Some("Be creative")
  assert opts.temperature == Some(0.9)
  assert opts.top_p == Some(0.95)
  assert opts.max_tokens == 4096
}

pub fn new_with_basic_test() {
  let opts = options()
  let req = new_with("claude-sonnet-4-20250514", [user_message("Hello")], opts)

  assert req.model == "claude-sonnet-4-20250514"
  assert req.max_tokens == 1024
  assert req.system == None
}

pub fn new_with_all_options_test() {
  let opts =
    options()
    |> opt_max_tokens(2048)
    |> opt_system("You are a poet")
    |> opt_temperature(0.8)
    |> opt_top_p(0.9)
    |> opt_top_k(50)
    |> opt_stop_sequences(["END"])

  let req =
    new_with("claude-sonnet-4-20250514", [user_message("Write a poem")], opts)

  assert req.model == "claude-sonnet-4-20250514"
  assert req.max_tokens == 2048
  assert req.system == Some("You are a poet")
  assert req.temperature == Some(0.8)
  assert req.top_p == Some(0.9)
  assert req.top_k == Some(50)
  assert req.stop_sequences == Some(["END"])
}

pub fn new_with_equivalent_to_new_with_builders_test() {
  // Create request using new() + builders
  let req1 =
    request_new("claude-sonnet-4-20250514", [user_message("Test")], 2048)
    |> with_system("Be helpful")
    |> with_temperature(0.7)

  // Create request using new_with() + options
  let opts =
    options()
    |> opt_max_tokens(2048)
    |> opt_system("Be helpful")
    |> opt_temperature(0.7)

  let req2 = new_with("claude-sonnet-4-20250514", [user_message("Test")], opts)

  // Both should produce equivalent results
  assert req1.model == req2.model
  assert req1.max_tokens == req2.max_tokens
  assert req1.system == req2.system
  assert req1.temperature == req2.temperature
}

pub fn get_options_extracts_all_fields_test() {
  let req =
    request_new("claude-sonnet-4-20250514", [user_message("Hello")], 2048)
    |> with_system("Be concise")
    |> with_temperature(0.5)
    |> with_top_p(0.9)
    |> with_top_k(40)

  let opts = get_options(req)

  assert opts.max_tokens == 2048
  assert opts.system == Some("Be concise")
  assert opts.temperature == Some(0.5)
  assert opts.top_p == Some(0.9)
  assert opts.top_k == Some(40)
}

pub fn get_options_roundtrip_test() {
  // Create options and make a request
  let original_opts =
    options()
    |> opt_max_tokens(1500)
    |> opt_system("Test system")
    |> opt_temperature(0.6)

  let req =
    new_with("claude-sonnet-4-20250514", [user_message("Test")], original_opts)

  // Extract options back
  let extracted_opts = get_options(req)

  // Options should match
  assert extracted_opts.max_tokens == original_opts.max_tokens
  assert extracted_opts.system == original_opts.system
  assert extracted_opts.temperature == original_opts.temperature
}

pub fn apply_options_basic_test() {
  let req = request_new("claude-sonnet-4-20250514", [user_message("Hi")], 1024)

  let opts =
    options()
    |> opt_temperature(0.8)
    |> opt_system("Be friendly")

  let updated = apply_options(req, opts)

  assert updated.model == "claude-sonnet-4-20250514"
  assert updated.temperature == Some(0.8)
  assert updated.system == Some("Be friendly")
}

pub fn apply_options_preserves_existing_when_none_test() {
  // Create request with some options set
  let req =
    request_new("claude-sonnet-4-20250514", [user_message("Hi")], 1024)
    |> with_system("Original system")
    |> with_temperature(0.5)

  // Apply options that only override temperature
  let opts = options() |> opt_temperature(0.9)

  let updated = apply_options(req, opts)

  // System should be preserved (opts.system is None)
  assert updated.system == Some("Original system")
  // Temperature should be updated
  assert updated.temperature == Some(0.9)
}

pub fn apply_options_overrides_when_set_test() {
  // Create request with system set
  let req =
    request_new("claude-sonnet-4-20250514", [user_message("Hi")], 1024)
    |> with_system("Original system")

  // Apply options that also set system
  let opts = options() |> opt_system("New system")

  let updated = apply_options(req, opts)

  // System should be overridden
  assert updated.system == Some("New system")
}

pub fn options_reusable_across_requests_test() {
  // Create reusable options
  let creative_opts =
    options()
    |> opt_system("You are a creative writer")
    |> opt_temperature(0.9)
    |> opt_max_tokens(2048)

  // Use for multiple requests
  let req1 =
    new_with(
      "claude-sonnet-4-20250514",
      [user_message("Write about stars")],
      creative_opts,
    )

  let req2 =
    new_with(
      "claude-sonnet-4-20250514",
      [user_message("Write about the ocean")],
      creative_opts,
    )

  // Both should have the same options
  assert req1.system == req2.system
  assert req1.temperature == req2.temperature
  assert req1.max_tokens == req2.max_tokens

  // But different messages
  assert req1.messages != req2.messages
}

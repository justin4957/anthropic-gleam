//// Testing utilities for Anthropic API client
////
//// This module provides mock responses, test fixtures, and helpers
//// for testing code that uses the anthropic_gleam library.

import anthropic/message
import anthropic/request.{type CreateMessageResponse}
import gleam/erlang/charlist
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{None, Some}

// =============================================================================
// Mock Response Builders
// =============================================================================

/// Create a mock successful text response
pub fn mock_text_response(text: String) -> Response(String) {
  response.new(200)
  |> response.set_body(mock_text_response_body("msg_mock_123", text))
}

/// Create a mock successful tool use response
pub fn mock_tool_use_response(
  tool_id: String,
  tool_name: String,
  tool_input: String,
) -> Response(String) {
  response.new(200)
  |> response.set_body(mock_tool_use_response_body(
    "msg_mock_456",
    tool_id,
    tool_name,
    tool_input,
  ))
}

/// Create a mock error response
pub fn mock_error_response(
  status_code: Int,
  error_type: String,
  message: String,
) -> Response(String) {
  response.new(status_code)
  |> response.set_body(mock_error_body(error_type, message))
}

/// Create a mock authentication error response
pub fn mock_auth_error() -> Response(String) {
  mock_error_response(401, "authentication_error", "Invalid API key")
}

/// Create a mock rate limit error response
pub fn mock_rate_limit_error() -> Response(String) {
  mock_error_response(429, "rate_limit_error", "Rate limit exceeded")
}

/// Create a mock overloaded error response
pub fn mock_overloaded_error() -> Response(String) {
  mock_error_response(529, "overloaded_error", "API is temporarily overloaded")
}

/// Create a mock invalid request error response
pub fn mock_invalid_request_error(message: String) -> Response(String) {
  mock_error_response(400, "invalid_request_error", message)
}

// =============================================================================
// Response Body Builders
// =============================================================================

/// Build a mock text response body JSON
pub fn mock_text_response_body(id: String, text: String) -> String {
  json.to_string(
    json.object([
      #("id", json.string(id)),
      #("type", json.string("message")),
      #("role", json.string("assistant")),
      #(
        "content",
        json.array(
          [
            json.object([
              #("type", json.string("text")),
              #("text", json.string(text)),
            ]),
          ],
          fn(x) { x },
        ),
      ),
      #("model", json.string("claude-sonnet-4-20250514")),
      #("stop_reason", json.string("end_turn")),
      #(
        "usage",
        json.object([
          #("input_tokens", json.int(10)),
          #("output_tokens", json.int(20)),
        ]),
      ),
    ]),
  )
}

/// Build a mock tool use response body JSON
pub fn mock_tool_use_response_body(
  id: String,
  tool_id: String,
  tool_name: String,
  _tool_input: String,
) -> String {
  // Note: tool_input is currently not used as we generate a mock empty object
  // In a real implementation, you might want to parse and include the input
  json.to_string(
    json.object([
      #("id", json.string(id)),
      #("type", json.string("message")),
      #("role", json.string("assistant")),
      #(
        "content",
        json.array(
          [
            json.object([
              #("type", json.string("tool_use")),
              #("id", json.string(tool_id)),
              #("name", json.string(tool_name)),
              #("input", json.object([])),
            ]),
          ],
          fn(x) { x },
        ),
      ),
      #("model", json.string("claude-sonnet-4-20250514")),
      #("stop_reason", json.string("tool_use")),
      #(
        "usage",
        json.object([
          #("input_tokens", json.int(15)),
          #("output_tokens", json.int(25)),
        ]),
      ),
    ]),
  )
}

/// Build a mock error body JSON
pub fn mock_error_body(error_type: String, message: String) -> String {
  json.to_string(
    json.object([
      #("type", json.string("error")),
      #(
        "error",
        json.object([
          #("type", json.string(error_type)),
          #("message", json.string(message)),
        ]),
      ),
    ]),
  )
}

// =============================================================================
// Test Fixtures
// =============================================================================

/// A simple text response fixture
pub fn fixture_simple_response() -> CreateMessageResponse {
  request.CreateMessageResponse(
    id: "msg_fixture_001",
    response_type: "message",
    role: message.Assistant,
    content: [message.TextBlock(text: "Hello! How can I help you today?")],
    model: "claude-sonnet-4-20250514",
    stop_reason: Some(request.EndTurn),
    stop_sequence: None,
    usage: request.Usage(input_tokens: 12, output_tokens: 8),
  )
}

/// A multi-turn conversation response fixture
pub fn fixture_conversation_response() -> CreateMessageResponse {
  request.CreateMessageResponse(
    id: "msg_fixture_002",
    response_type: "message",
    role: message.Assistant,
    content: [
      message.TextBlock(
        text: "Based on our previous conversation, I understand you're asking about Gleam programming.",
      ),
    ],
    model: "claude-sonnet-4-20250514",
    stop_reason: Some(request.EndTurn),
    stop_sequence: None,
    usage: request.Usage(input_tokens: 150, output_tokens: 45),
  )
}

/// A tool use response fixture
pub fn fixture_tool_use_response() -> CreateMessageResponse {
  request.CreateMessageResponse(
    id: "msg_fixture_003",
    response_type: "message",
    role: message.Assistant,
    content: [
      message.TextBlock(text: "Let me check the weather for you."),
      message.ToolUseBlock(
        id: "toolu_fixture_001",
        name: "get_weather",
        input: "{\"location\":\"San Francisco\",\"unit\":\"celsius\"}",
      ),
    ],
    model: "claude-sonnet-4-20250514",
    stop_reason: Some(request.ToolUse),
    stop_sequence: None,
    usage: request.Usage(input_tokens: 25, output_tokens: 35),
  )
}

/// A max tokens response fixture
pub fn fixture_max_tokens_response() -> CreateMessageResponse {
  request.CreateMessageResponse(
    id: "msg_fixture_004",
    response_type: "message",
    role: message.Assistant,
    content: [
      message.TextBlock(
        text: "This response was truncated because it reached the maximum token limit...",
      ),
    ],
    model: "claude-sonnet-4-20250514",
    stop_reason: Some(request.MaxTokens),
    stop_sequence: None,
    usage: request.Usage(input_tokens: 20, output_tokens: 100),
  )
}

/// A stop sequence response fixture
pub fn fixture_stop_sequence_response() -> CreateMessageResponse {
  request.CreateMessageResponse(
    id: "msg_fixture_005",
    response_type: "message",
    role: message.Assistant,
    content: [message.TextBlock(text: "The answer is 42")],
    model: "claude-sonnet-4-20250514",
    stop_reason: Some(request.StopSequence),
    stop_sequence: Some("END"),
    usage: request.Usage(input_tokens: 15, output_tokens: 5),
  )
}

// =============================================================================
// Integration Test Helpers
// =============================================================================

/// Check if an API key is available for integration tests
pub fn has_api_key() -> Bool {
  case get_env("ANTHROPIC_API_KEY") {
    Ok(key) -> key != ""
    Error(_) -> False
  }
}

/// Get environment variable using charlist conversion
@external(erlang, "os", "getenv")
fn ffi_getenv(
  name: charlist.Charlist,
  default: charlist.Charlist,
) -> charlist.Charlist

fn get_env(name: String) -> Result(String, Nil) {
  let value =
    ffi_getenv(charlist.from_string(name), charlist.from_string(""))
    |> charlist.to_string
  case value {
    "" -> Error(Nil)
    v -> Ok(v)
  }
}

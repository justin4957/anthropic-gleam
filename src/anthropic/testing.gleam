//// Testing utilities for Anthropic API client
////
//// This module provides mock responses, test fixtures, and helpers
//// for testing code that uses the anthropic_gleam library.
////
//// ## Two Categories of Test Helpers
////
//// This module provides two distinct categories of testing utilities:
////
//// ### 1. HTTP Response Mocks (`mock_*` functions)
////
//// These functions return `Response(String)` - raw HTTP responses with JSON bodies.
//// Use these when testing code that handles HTTP responses directly, such as
//// custom HTTP clients or sans-io patterns.
////
//// ```gleam
//// // Returns Response(String) - an HTTP response
//// let http_response = mock_text_response("Hello!")
////
//// // To get a CreateMessageResponse, parse it:
//// let assert Ok(parsed) = http.parse_messages_response(http_response)
//// ```
////
//// ### 2. Fixture Responses (`fixture_*` functions)
////
//// These functions return `CreateMessageResponse` - pre-parsed domain objects.
//// Use these when testing business logic that works with parsed responses.
////
//// ```gleam
//// // Returns CreateMessageResponse directly
//// let response = fixture_simple_response()
//// let text = request.response_text(response)
//// ```
////
//// ## Quick Reference
////
//// | Function | Returns | Use Case |
//// |----------|---------|----------|
//// | `mock_response(text)` | `CreateMessageResponse` | Simple testing with custom text |
//// | `mock_text_response(text)` | `Response(String)` | HTTP layer testing |
//// | `mock_tool_use_response(...)` | `Response(String)` | HTTP layer testing |
//// | `mock_error_response(...)` | `Response(String)` | HTTP error handling |
//// | `fixture_simple_response()` | `CreateMessageResponse` | Business logic testing |
//// | `fixture_tool_use_response()` | `CreateMessageResponse` | Tool use testing |
////
//// ## Example: Testing Business Logic
////
//// ```gleam
//// import anthropic/testing.{mock_response, fixture_tool_use_response}
//// import anthropic/request
////
//// pub fn test_response_handling() {
////   // Use mock_response for simple custom text
////   let response = mock_response("The answer is 42")
////   let text = request.response_text(response)
////   assert text == "The answer is 42"
////
////   // Use fixtures for specific scenarios
////   let tool_response = fixture_tool_use_response()
////   assert request.needs_tool_execution(tool_response) == True
//// }
//// ```
////
//// ## Example: Testing HTTP Handling
////
//// ```gleam
//// import anthropic/testing.{mock_text_response, mock_rate_limit_error}
//// import anthropic/http
////
//// pub fn test_http_parsing() {
////   // Test successful response parsing
////   let http_response = mock_text_response("Hello!")
////   let assert Ok(parsed) = http.parse_messages_response(http_response)
////
////   // Test error handling
////   let error_response = mock_rate_limit_error()
////   let assert Error(err) = http.parse_messages_response(error_response)
//// }
//// ```

import anthropic/message
import anthropic/request.{type CreateMessageResponse}
import gleam/erlang/charlist
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/option.{None, Some}

// =============================================================================
// Convenience Response Builder
// =============================================================================

/// Create a mock CreateMessageResponse with custom text
///
/// This is the simplest way to create a test response. Returns a parsed
/// `CreateMessageResponse` directly, ready to use with functions like
/// `request.response_text()`.
///
/// ## Example
///
/// ```gleam
/// let response = mock_response("Hello from Claude!")
/// let text = request.response_text(response)
/// assert text == "Hello from Claude!"
/// ```
///
/// For more control over the response, use `mock_response_with()` or
/// the `fixture_*` functions.
pub fn mock_response(text: String) -> CreateMessageResponse {
  request.CreateMessageResponse(
    id: "msg_mock_" <> int.to_string(unique_id()),
    response_type: "message",
    role: message.Assistant,
    content: [message.TextBlock(text: text)],
    model: "claude-sonnet-4-20250514",
    stop_reason: Some(request.EndTurn),
    stop_sequence: None,
    usage: request.Usage(input_tokens: 10, output_tokens: 20),
  )
}

/// Create a mock CreateMessageResponse with custom options
///
/// Allows customizing the model, stop reason, and token usage.
///
/// ## Example
///
/// ```gleam
/// let response = mock_response_with(
///   "Generated text",
///   model: "claude-opus-4-20250514",
///   stop_reason: Some(request.MaxTokens),
///   input_tokens: 100,
///   output_tokens: 500,
/// )
/// ```
pub fn mock_response_with(
  text: String,
  model model: String,
  stop_reason stop_reason: option.Option(request.StopReason),
  input_tokens input_tokens: Int,
  output_tokens output_tokens: Int,
) -> CreateMessageResponse {
  request.CreateMessageResponse(
    id: "msg_mock_" <> int.to_string(unique_id()),
    response_type: "message",
    role: message.Assistant,
    content: [message.TextBlock(text: text)],
    model: model,
    stop_reason: stop_reason,
    stop_sequence: None,
    usage: request.Usage(
      input_tokens: input_tokens,
      output_tokens: output_tokens,
    ),
  )
}

// =============================================================================
// HTTP Response Mocks
// =============================================================================
//
// These functions return Response(String) - raw HTTP responses with JSON bodies.
// Use these when testing code that handles HTTP responses directly.

/// Create a mock HTTP response with text content
///
/// Returns a `Response(String)` representing an HTTP response from the API.
/// Use this when testing HTTP handling code. To get a `CreateMessageResponse`,
/// parse it with `http.parse_messages_response()`.
///
/// ## Example
///
/// ```gleam
/// let http_response = mock_text_response("Hello!")
/// // http_response.status == 200
/// // http_response.body contains JSON
///
/// // To parse into CreateMessageResponse:
/// let assert Ok(parsed) = http.parse_messages_response(http_response)
/// ```
///
/// For a simpler API that returns `CreateMessageResponse` directly,
/// use `mock_response()` instead.
pub fn mock_text_response(text: String) -> Response(String) {
  response.new(200)
  |> response.set_body(mock_text_response_body("msg_mock_123", text))
}

/// Create a mock HTTP response with tool use content
///
/// Returns a `Response(String)` representing an HTTP response with tool use.
/// Use this when testing HTTP handling code for tool use scenarios.
///
/// ## Example
///
/// ```gleam
/// let http_response = mock_tool_use_response(
///   "toolu_123",
///   "get_weather",
///   "{\"location\": \"Paris\"}",
/// )
/// let assert Ok(parsed) = http.parse_messages_response(http_response)
/// ```
///
/// For pre-parsed tool use responses, use `fixture_tool_use_response()`.
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

/// Create a mock HTTP error response
///
/// Returns a `Response(String)` representing an HTTP error response.
/// Use this when testing error handling code.
///
/// ## Example
///
/// ```gleam
/// let http_response = mock_error_response(400, "invalid_request_error", "Bad request")
/// let assert Error(err) = http.parse_messages_response(http_response)
/// ```
pub fn mock_error_response(
  status_code: Int,
  error_type: String,
  error_message: String,
) -> Response(String) {
  response.new(status_code)
  |> response.set_body(mock_error_body(error_type, error_message))
}

/// Create a mock HTTP authentication error response (401)
pub fn mock_auth_error() -> Response(String) {
  mock_error_response(401, "authentication_error", "Invalid API key")
}

/// Create a mock HTTP rate limit error response (429)
pub fn mock_rate_limit_error() -> Response(String) {
  mock_error_response(429, "rate_limit_error", "Rate limit exceeded")
}

/// Create a mock HTTP overloaded error response (529)
pub fn mock_overloaded_error() -> Response(String) {
  mock_error_response(529, "overloaded_error", "API is temporarily overloaded")
}

/// Create a mock HTTP invalid request error response (400)
pub fn mock_invalid_request_error(error_message: String) -> Response(String) {
  mock_error_response(400, "invalid_request_error", error_message)
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
// Test Fixtures (Pre-parsed CreateMessageResponse objects)
// =============================================================================
//
// These functions return CreateMessageResponse directly - parsed domain objects
// ready to use with request.response_text(), request.needs_tool_execution(), etc.
//
// Use these when testing business logic that works with parsed responses.

/// A simple text response fixture
///
/// Returns a `CreateMessageResponse` with a simple greeting text.
/// Use this for basic response handling tests.
///
/// ## Example
///
/// ```gleam
/// let response = fixture_simple_response()
/// let text = request.response_text(response)
/// // text == "Hello! How can I help you today?"
/// ```
///
/// For custom text, use `mock_response(text)` instead.
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
///
/// Returns a `CreateMessageResponse` simulating a response in an ongoing conversation.
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
///
/// Returns a `CreateMessageResponse` with tool use content.
/// Use this when testing tool execution workflows.
///
/// ## Example
///
/// ```gleam
/// let response = fixture_tool_use_response()
/// assert request.needs_tool_execution(response) == True
/// let calls = request.get_pending_tool_calls(response)
/// ```
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
///
/// Returns a `CreateMessageResponse` that was truncated due to max_tokens limit.
/// Use this when testing handling of truncated responses.
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
///
/// Returns a `CreateMessageResponse` that stopped due to a custom stop sequence.
/// Use this when testing stop sequence handling.
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

// =============================================================================
// Internal Helpers
// =============================================================================

/// Generate a unique ID for mock responses
fn unique_id() -> Int {
  // Use erlang's unique_integer with [positive] option for guaranteed uniqueness
  erlang_unique_integer_positive()
}

@external(erlang, "anthropic_testing_ffi", "unique_integer")
fn erlang_unique_integer_positive() -> Int

//// API functions for Anthropic Messages API
////
//// This module provides the core functions for interacting with Claude's
//// Messages API, including message creation and response parsing.

import anthropic/client.{type Client, messages_endpoint}
import anthropic/types/decoder
import anthropic/types/error.{type AnthropicError}
import anthropic/types/request.{
  type CreateMessageRequest, type CreateMessageResponse,
}
import gleam/list
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
  decoder.parse_response_body(body)
}

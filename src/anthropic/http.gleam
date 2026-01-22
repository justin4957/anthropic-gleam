//// HTTP types and request/response builders for sans-io pattern
////
//// This module provides HTTP-library-agnostic types for building requests
//// and parsing responses. Users can use any HTTP client by:
////
//// 1. Building a request with `build_messages_request`
//// 2. Sending it with their preferred HTTP client
//// 3. Parsing the response with `parse_messages_response`
////
//// ## Example with custom HTTP client
////
//// ```gleam
//// import anthropic/http
//// import anthropic/types/request
////
//// // Build the request
//// let api_request = request.create_request(
////   "claude-sonnet-4-20250514",
////   [request.user_message("Hello!")],
////   1024,
//// )
//// let http_request = http.build_messages_request(config, api_request)
////
//// // Send with your HTTP client (e.g., hackney, httpc, fetch on JS)
//// let http_response = my_http_client.send(http_request)
////
//// // Parse the response
//// case http.parse_messages_response(http_response) {
////   Ok(response) -> io.println(request.response_text(response))
////   Error(err) -> io.println(error.error_to_string(err))
//// }
//// ```

import anthropic/types/decoder
import anthropic/types/error.{
  type AnthropicError, type ApiErrorType, AuthenticationError, InternalApiError,
  InvalidRequestError, NotFoundError, OverloadedError, PermissionError,
  RateLimitError,
}
import anthropic/types/request.{
  type CreateMessageRequest, type CreateMessageResponse,
}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// =============================================================================
// Constants
// =============================================================================

/// Current Anthropic API version header value
pub const api_version = "2023-06-01"

/// Messages API endpoint path
pub const messages_endpoint = "/v1/messages"

/// Default Anthropic API base URL
pub const default_base_url = "https://api.anthropic.com"

// =============================================================================
// HTTP Request Types (Sans-IO)
// =============================================================================

/// HTTP method
pub type Method {
  Get
  Post
  Put
  Delete
  Patch
}

/// HTTP request representation (HTTP-library agnostic)
pub type HttpRequest {
  HttpRequest(
    /// HTTP method
    method: Method,
    /// Full URL including base URL and path
    url: String,
    /// Request headers as key-value pairs
    headers: List(#(String, String)),
    /// Request body (JSON string)
    body: String,
  )
}

/// HTTP response representation (HTTP-library agnostic)
pub type HttpResponse {
  HttpResponse(
    /// HTTP status code
    status: Int,
    /// Response headers as key-value pairs
    headers: List(#(String, String)),
    /// Response body
    body: String,
  )
}

// =============================================================================
// Request Building (Sans-IO)
// =============================================================================

/// Build an HTTP request for the Messages API
///
/// This function creates an HTTP-library-agnostic request that can be
/// sent using any HTTP client. It handles:
/// - URL construction
/// - Authentication headers
/// - Content-Type and API version headers
/// - JSON body encoding
///
/// ## Example
///
/// ```gleam
/// let request = create_request("claude-sonnet-4-20250514", messages, 1024)
/// let http_req = build_messages_request("sk-ant-...", default_base_url, request)
/// // Send http_req with your HTTP client
/// ```
pub fn build_messages_request(
  api_key: String,
  base_url: String,
  message_request: CreateMessageRequest,
) -> HttpRequest {
  let url = base_url <> messages_endpoint
  let body = request.request_to_json_string(message_request)

  HttpRequest(
    method: Post,
    url: url,
    headers: build_headers(api_key, False),
    body: body,
  )
}

/// Build an HTTP request for streaming Messages API
///
/// Similar to `build_messages_request` but adds the Accept header for SSE
/// and ensures the stream flag is set on the request.
pub fn build_streaming_request(
  api_key: String,
  base_url: String,
  message_request: CreateMessageRequest,
) -> HttpRequest {
  let streaming_request = request.with_stream(message_request, True)
  let url = base_url <> messages_endpoint
  let body = request.request_to_json_string(streaming_request)

  HttpRequest(
    method: Post,
    url: url,
    headers: build_headers(api_key, True),
    body: body,
  )
}

/// Build standard Anthropic API headers
fn build_headers(api_key: String, streaming: Bool) -> List(#(String, String)) {
  let base_headers = [
    #("content-type", "application/json"),
    #("x-api-key", api_key),
    #("anthropic-version", api_version),
  ]

  case streaming {
    True -> list.append(base_headers, [#("accept", "text/event-stream")])
    False -> base_headers
  }
}

/// Convert Method to string for HTTP libraries that need it
pub fn method_to_string(method: Method) -> String {
  case method {
    Get -> "GET"
    Post -> "POST"
    Put -> "PUT"
    Delete -> "DELETE"
    Patch -> "PATCH"
  }
}

// =============================================================================
// Response Parsing (Sans-IO)
// =============================================================================

/// Parse an HTTP response into a CreateMessageResponse
///
/// This function handles:
/// - Status code checking (success vs error)
/// - Error response parsing with proper error types
/// - Success response JSON decoding
///
/// ## Example
///
/// ```gleam
/// let http_response = HttpResponse(status: 200, headers: [], body: json_body)
/// case parse_messages_response(http_response) {
///   Ok(response) -> handle_success(response)
///   Error(err) -> handle_error(err)
/// }
/// ```
pub fn parse_messages_response(
  response: HttpResponse,
) -> Result(CreateMessageResponse, AnthropicError) {
  case check_status(response) {
    Ok(body) -> parse_response_body(body)
    Error(err) -> Error(err)
  }
}

/// Check HTTP status and extract body or error
pub fn check_status(response: HttpResponse) -> Result(String, AnthropicError) {
  let status = response.status

  case status {
    // Success responses
    200 -> Ok(response.body)

    // Client errors
    400 -> Error(parse_api_error(status, response.body, InvalidRequestError))
    401 -> Error(parse_api_error(status, response.body, AuthenticationError))
    403 -> Error(parse_api_error(status, response.body, PermissionError))
    404 -> Error(parse_api_error(status, response.body, NotFoundError))
    429 -> Error(parse_api_error(status, response.body, RateLimitError))

    // Server errors
    500 -> Error(parse_api_error(status, response.body, InternalApiError))
    529 -> Error(parse_api_error(status, response.body, OverloadedError))

    // Other 4xx errors
    _ if status >= 400 && status < 500 ->
      Error(parse_api_error(status, response.body, InvalidRequestError))

    // Other 5xx errors
    _ if status >= 500 ->
      Error(parse_api_error(status, response.body, InternalApiError))

    // Unexpected status codes
    _ ->
      Error(error.http_error(
        "Unexpected status code: " <> string.inspect(status),
      ))
  }
}

/// Parse successful response body into CreateMessageResponse
pub fn parse_response_body(
  body: String,
) -> Result(CreateMessageResponse, AnthropicError) {
  decoder.parse_response_body(body)
}

// =============================================================================
// Error Response Parsing
// =============================================================================

/// Parse an error response body into ApiError
fn parse_api_error(
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

/// Error details decoder
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

/// Error wrapper decoder
fn error_wrapper_decoder() -> decode.Decoder(
  #(ApiErrorType, String, Option(String), Option(String)),
) {
  use details <- decode.field("error", error_details_decoder())
  decode.success(details)
}

/// Parse error body JSON
fn parse_error_body(
  body: String,
) -> Result(#(ApiErrorType, String, Option(String), Option(String)), Nil) {
  case decoder.parse_json(body) {
    Ok(dyn) ->
      case decode.run(dyn, error_wrapper_decoder()) {
        Ok(details) -> Ok(details)
        Error(_) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

// =============================================================================
// Validation
// =============================================================================

/// Validate a CreateMessageRequest before sending
///
/// This performs client-side validation to catch errors early.
pub fn validate_request(
  req: CreateMessageRequest,
) -> Result(Nil, AnthropicError) {
  case list.is_empty(req.messages) {
    True -> Error(error.invalid_request_error("messages list cannot be empty"))
    False -> Ok(Nil)
  }
  |> result.try(fn(_) {
    case string.is_empty(string.trim(req.model)) {
      True -> Error(error.invalid_request_error("model name cannot be empty"))
      False -> Ok(Nil)
    }
  })
  |> result.try(fn(_) {
    case req.max_tokens > 0 {
      True -> Ok(Nil)
      False ->
        Error(error.invalid_request_error("max_tokens must be greater than 0"))
    }
  })
}

//// HTTP client wrapper for Anthropic API calls
////
//// This module provides a client for making requests to the Anthropic Messages API,
//// handling headers, timeouts, and response parsing.

import anthropic/config.{type Config}
import anthropic/types/error.{
  type AnthropicError, type ApiErrorType, AuthenticationError, InternalApiError,
  InvalidRequestError, NotFoundError, OverloadedError, PermissionError,
  RateLimitError,
}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/option.{None, Some}
import gleam/result
import gleam/string

// =============================================================================
// Constants
// =============================================================================

/// Current Anthropic API version
pub const api_version = "2023-06-01"

/// Messages API endpoint path
pub const messages_endpoint = "/v1/messages"

// =============================================================================
// Client Type
// =============================================================================

/// Client for making Anthropic API requests
pub type Client {
  Client(
    /// Configuration including API key and base URL
    config: Config,
  )
}

/// Create a new client from configuration
pub fn new(config: Config) -> Client {
  Client(config: config)
}

// =============================================================================
// HTTP Requests
// =============================================================================

/// Make a POST request with JSON body to the specified path
pub fn post_json(
  client: Client,
  path: String,
  body: String,
) -> Result(Response(String), AnthropicError) {
  // Build the request
  let base_url = client.config.base_url
  let full_url = base_url <> path

  // Parse the URL and create request
  use req <- result.try(
    request.to(full_url)
    |> result.map_error(fn(_) {
      error.config_error("Invalid URL: " <> full_url)
    }),
  )

  // Set headers and body
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_header("x-api-key", client.config.api_key)
    |> request.set_header("anthropic-version", api_version)
    |> request.set_body(body)

  // Make the request
  httpc.send(req)
  |> result.map_error(fn(err) { http_error_to_anthropic_error(err) })
}

/// Convert httpc error to AnthropicError
fn http_error_to_anthropic_error(err: httpc.HttpError) -> AnthropicError {
  case err {
    httpc.InvalidUtf8Response -> error.http_error("Invalid UTF-8 in response")
    httpc.FailedToConnect(ip4, ip6) ->
      error.network_error(
        "Failed to connect to server (IPv4: "
        <> connect_error_to_string(ip4)
        <> ", IPv6: "
        <> connect_error_to_string(ip6)
        <> ")",
      )
    httpc.ResponseTimeout -> error.timeout_error(0)
  }
}

/// Convert ConnectError to string
fn connect_error_to_string(err: httpc.ConnectError) -> String {
  case err {
    httpc.Posix(code) -> "POSIX error: " <> code
    httpc.TlsAlert(code, detail) -> "TLS alert " <> code <> ": " <> detail
  }
}

// =============================================================================
// Response Handling
// =============================================================================

/// Handle an API response, parsing success or error
pub fn handle_response(
  response: Response(String),
) -> Result(String, AnthropicError) {
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

/// Parse an error response body into ApiError
fn parse_api_error(
  status_code: Int,
  body: String,
  default_type: ApiErrorType,
) -> AnthropicError {
  // Try to parse the error response using JSON decoding
  case parse_error_body(body) {
    Ok(#(error_type, message, param, code)) ->
      error.api_error(
        status_code,
        error.api_error_details_full(error_type, message, param, code),
      )
    Error(_) ->
      // Fallback to default error type with body as message
      error.api_error(status_code, error.api_error_details(default_type, body))
  }
}

/// Parse a JSON string to Dynamic
@external(erlang, "gleam_json_ffi", "decode")
fn parse_json_to_dynamic(json: String) -> Result(Dynamic, Nil)

/// Error details decoder
fn error_details_decoder() -> decode.Decoder(
  #(ApiErrorType, String, option.Option(String), option.Option(String)),
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
  #(ApiErrorType, String, option.Option(String), option.Option(String)),
) {
  use details <- decode.field("error", error_details_decoder())
  decode.success(details)
}

/// Parse error body JSON
fn parse_error_body(
  body: String,
) -> Result(
  #(ApiErrorType, String, option.Option(String), option.Option(String)),
  Nil,
) {
  // Anthropic error format: {"type": "error", "error": {"type": "...", "message": "..."}}
  case parse_json_to_dynamic(body) {
    Ok(dyn) ->
      case decode.run(dyn, error_wrapper_decoder()) {
        Ok(details) -> Ok(details)
        Error(_) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

// =============================================================================
// High-Level Request Functions
// =============================================================================

/// Make a POST request and handle the response
pub fn post_and_handle(
  client: Client,
  path: String,
  body: String,
) -> Result(String, AnthropicError) {
  use response <- result.try(post_json(client, path, body))
  handle_response(response)
}

//// Error types for Anthropic API interactions
////
//// This module defines comprehensive error types that can occur when
//// interacting with the Anthropic Messages API.

import gleam/int
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

// =============================================================================
// ApiErrorType - Specific API error categories
// =============================================================================

/// Type of API error returned by Anthropic
pub type ApiErrorType {
  /// Invalid authentication credentials
  AuthenticationError
  /// Invalid request parameters or format
  InvalidRequestError
  /// Rate limit exceeded
  RateLimitError
  /// Internal API error
  InternalApiError
  /// API is overloaded
  OverloadedError
  /// Permission denied for the requested resource
  PermissionError
  /// Requested resource not found
  NotFoundError
  /// Unknown error type
  UnknownApiError(String)
}

/// Convert an API error type string to ApiErrorType
pub fn api_error_type_from_string(str: String) -> ApiErrorType {
  case str {
    "authentication_error" -> AuthenticationError
    "invalid_request_error" -> InvalidRequestError
    "rate_limit_error" -> RateLimitError
    "api_error" -> InternalApiError
    "overloaded_error" -> OverloadedError
    "permission_error" -> PermissionError
    "not_found_error" -> NotFoundError
    _ -> UnknownApiError(str)
  }
}

/// Convert an ApiErrorType to its string representation
pub fn api_error_type_to_string(error_type: ApiErrorType) -> String {
  case error_type {
    AuthenticationError -> "authentication_error"
    InvalidRequestError -> "invalid_request_error"
    RateLimitError -> "rate_limit_error"
    InternalApiError -> "api_error"
    OverloadedError -> "overloaded_error"
    PermissionError -> "permission_error"
    NotFoundError -> "not_found_error"
    UnknownApiError(s) -> s
  }
}

// =============================================================================
// ApiErrorDetails - Details from API error response
// =============================================================================

/// Details from an API error response
pub type ApiErrorDetails {
  ApiErrorDetails(
    /// The type of error
    error_type: ApiErrorType,
    /// Human-readable error message
    message: String,
    /// Optional parameter that caused the error
    param: Option(String),
    /// Optional error code
    code: Option(String),
  )
}

/// Create ApiErrorDetails with just type and message
pub fn api_error_details(
  error_type: ApiErrorType,
  message: String,
) -> ApiErrorDetails {
  ApiErrorDetails(
    error_type: error_type,
    message: message,
    param: None,
    code: None,
  )
}

/// Create ApiErrorDetails with all fields
pub fn api_error_details_full(
  error_type: ApiErrorType,
  message: String,
  param: Option(String),
  code: Option(String),
) -> ApiErrorDetails {
  ApiErrorDetails(
    error_type: error_type,
    message: message,
    param: param,
    code: code,
  )
}

/// Convert ApiErrorDetails to a display string
pub fn api_error_details_to_string(details: ApiErrorDetails) -> String {
  let base =
    api_error_type_to_string(details.error_type) <> ": " <> details.message

  let with_param = case details.param {
    Some(p) -> base <> " (param: " <> p <> ")"
    None -> base
  }

  case details.code {
    Some(c) -> with_param <> " [code: " <> c <> "]"
    None -> with_param
  }
}

// =============================================================================
// AnthropicError - Main error type
// =============================================================================

/// Comprehensive error type for Anthropic API interactions
pub type AnthropicError {
  /// Error returned by the Anthropic API
  ApiError(
    /// HTTP status code
    status_code: Int,
    /// Error details from the response
    details: ApiErrorDetails,
  )

  /// HTTP transport error (connection failed, timeout, etc.)
  HttpError(
    /// Description of the HTTP error
    reason: String,
  )

  /// JSON encoding or decoding error
  JsonError(
    /// Description of what went wrong
    reason: String,
  )

  /// Configuration error (missing API key, invalid settings)
  ConfigError(
    /// Description of the configuration problem
    reason: String,
  )

  /// Request timeout
  TimeoutError(
    /// Timeout duration in milliseconds
    timeout_ms: Int,
  )

  /// Network connectivity error
  NetworkError(
    /// Description of the network issue
    reason: String,
  )
}

// =============================================================================
// Error constructors
// =============================================================================

/// Create an API error with status code and details
pub fn api_error(status_code: Int, details: ApiErrorDetails) -> AnthropicError {
  ApiError(status_code: status_code, details: details)
}

/// Create an authentication error
pub fn authentication_error(message: String) -> AnthropicError {
  ApiError(
    status_code: 401,
    details: api_error_details(AuthenticationError, message),
  )
}

/// Create an invalid request error
pub fn invalid_request_error(message: String) -> AnthropicError {
  ApiError(
    status_code: 400,
    details: api_error_details(InvalidRequestError, message),
  )
}

/// Create a rate limit error
pub fn rate_limit_error(message: String) -> AnthropicError {
  ApiError(
    status_code: 429,
    details: api_error_details(RateLimitError, message),
  )
}

/// Create an internal API error
pub fn internal_api_error(message: String) -> AnthropicError {
  ApiError(
    status_code: 500,
    details: api_error_details(InternalApiError, message),
  )
}

/// Create an overloaded error
pub fn overloaded_error(message: String) -> AnthropicError {
  ApiError(
    status_code: 529,
    details: api_error_details(OverloadedError, message),
  )
}

/// Create an HTTP error
pub fn http_error(reason: String) -> AnthropicError {
  HttpError(reason: reason)
}

/// Create a JSON error
pub fn json_error(reason: String) -> AnthropicError {
  JsonError(reason: reason)
}

/// Create a configuration error
pub fn config_error(reason: String) -> AnthropicError {
  ConfigError(reason: reason)
}

/// Create a timeout error
pub fn timeout_error(timeout_ms: Int) -> AnthropicError {
  TimeoutError(timeout_ms: timeout_ms)
}

/// Create a network error
pub fn network_error(reason: String) -> AnthropicError {
  NetworkError(reason: reason)
}

/// Create a missing API key error
pub fn missing_api_key_error() -> AnthropicError {
  ConfigError(reason: "API key is required but not provided")
}

/// Create an invalid API key error
pub fn invalid_api_key_error() -> AnthropicError {
  ConfigError(reason: "API key format is invalid")
}

// =============================================================================
// Error display
// =============================================================================

/// Convert an AnthropicError to a human-readable string
pub fn error_to_string(error: AnthropicError) -> String {
  case error {
    ApiError(status_code: status, details: details) ->
      "API Error ("
      <> int.to_string(status)
      <> "): "
      <> api_error_details_to_string(details)

    HttpError(reason: reason) -> "HTTP Error: " <> reason

    JsonError(reason: reason) -> "JSON Error: " <> reason

    ConfigError(reason: reason) -> "Configuration Error: " <> reason

    TimeoutError(timeout_ms: ms) ->
      "Timeout Error: Request timed out after " <> int.to_string(ms) <> "ms"

    NetworkError(reason: reason) -> "Network Error: " <> reason
  }
}

/// Get the error category as a string
pub fn error_category(error: AnthropicError) -> String {
  case error {
    ApiError(_, _) -> "api"
    HttpError(_) -> "http"
    JsonError(_) -> "json"
    ConfigError(_) -> "config"
    TimeoutError(_) -> "timeout"
    NetworkError(_) -> "network"
  }
}

// =============================================================================
// Error predicates
// =============================================================================

/// Check if an error is retryable
pub fn is_retryable(error: AnthropicError) -> Bool {
  case error {
    ApiError(status_code: status, details: details) ->
      case details.error_type {
        RateLimitError -> True
        OverloadedError -> True
        InternalApiError -> status >= 500
        _ -> False
      }
    HttpError(_) -> True
    TimeoutError(_) -> True
    NetworkError(_) -> True
    JsonError(_) -> False
    ConfigError(_) -> False
  }
}

/// Check if an error is an authentication error
pub fn is_authentication_error(error: AnthropicError) -> Bool {
  case error {
    ApiError(_, details) ->
      case details.error_type {
        AuthenticationError -> True
        _ -> False
      }
    _ -> False
  }
}

/// Check if an error is a rate limit error
pub fn is_rate_limit_error(error: AnthropicError) -> Bool {
  case error {
    ApiError(_, details) ->
      case details.error_type {
        RateLimitError -> True
        _ -> False
      }
    _ -> False
  }
}

/// Check if an error is an overloaded error
pub fn is_overloaded_error(error: AnthropicError) -> Bool {
  case error {
    ApiError(_, details) ->
      case details.error_type {
        OverloadedError -> True
        _ -> False
      }
    _ -> False
  }
}

/// Get the HTTP status code if this is an API error
pub fn get_status_code(error: AnthropicError) -> Option(Int) {
  case error {
    ApiError(status_code: status, details: _) -> Some(status)
    _ -> None
  }
}

// =============================================================================
// JSON encoding
// =============================================================================

/// Encode an ApiErrorDetails to JSON
pub fn api_error_details_to_json(details: ApiErrorDetails) -> Json {
  let base_fields = [
    #("type", json.string(api_error_type_to_string(details.error_type))),
    #("message", json.string(details.message)),
  ]

  let with_param = case details.param {
    Some(p) -> [#("param", json.string(p)), ..base_fields]
    None -> base_fields
  }

  let with_code = case details.code {
    Some(c) -> [#("code", json.string(c)), ..with_param]
    None -> with_param
  }

  json.object(with_code)
}

/// Encode an AnthropicError to JSON
pub fn error_to_json(error: AnthropicError) -> Json {
  case error {
    ApiError(status_code: status, details: details) ->
      json.object([
        #("category", json.string("api")),
        #("status_code", json.int(status)),
        #("error", api_error_details_to_json(details)),
      ])

    HttpError(reason: reason) ->
      json.object([
        #("category", json.string("http")),
        #("reason", json.string(reason)),
      ])

    JsonError(reason: reason) ->
      json.object([
        #("category", json.string("json")),
        #("reason", json.string(reason)),
      ])

    ConfigError(reason: reason) ->
      json.object([
        #("category", json.string("config")),
        #("reason", json.string(reason)),
      ])

    TimeoutError(timeout_ms: ms) ->
      json.object([
        #("category", json.string("timeout")),
        #("timeout_ms", json.int(ms)),
      ])

    NetworkError(reason: reason) ->
      json.object([
        #("category", json.string("network")),
        #("reason", json.string(reason)),
      ])
  }
}

/// Convert an error to a JSON string
pub fn error_to_json_string(error: AnthropicError) -> String {
  error
  |> error_to_json
  |> json.to_string
}

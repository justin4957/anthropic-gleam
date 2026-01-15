//// Configuration management for the Anthropic client
////
//// This module defines the configuration structure and helpers for loading
//// settings from explicit options or environment variables.

import anthropic/types/error.{type AnthropicError, config_error}
import gleam/erlang/charlist
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// =============================================================================
// Defaults
// =============================================================================

/// Default Anthropic API base URL
pub const default_base_url = "https://api.anthropic.com"

/// Default request timeout in milliseconds
pub const default_timeout_ms = 60_000

/// Default retry count for transient failures
pub const default_max_retries = 3

// =============================================================================
// Types
// =============================================================================

/// Configuration for Anthropic client requests
pub type Config {
  Config(
    /// API key used for authentication
    api_key: String,
    /// Base URL for Anthropic API requests
    base_url: String,
    /// Optional default model name
    default_model: Option(String),
    /// Request timeout in milliseconds
    timeout_ms: Int,
    /// Number of retries for retryable errors
    max_retries: Int,
  )
}

/// Optional configuration inputs used when loading configuration
pub type ConfigOptions {
  ConfigOptions(
    /// Explicit API key (takes precedence over environment variables)
    api_key: Option(String),
    /// Custom API base URL
    base_url: Option(String),
    /// Default model to use for requests
    default_model: Option(String),
    /// Request timeout in milliseconds
    timeout_ms: Option(Int),
    /// Retry count for transient errors
    max_retries: Option(Int),
  )
}

// =============================================================================
// Constructors
// =============================================================================

/// Create empty configuration options
pub fn config_options() -> ConfigOptions {
  ConfigOptions(
    api_key: None,
    base_url: None,
    default_model: None,
    timeout_ms: None,
    max_retries: None,
  )
}

/// Set an explicit API key on configuration options
pub fn with_api_key(options: ConfigOptions, api_key: String) -> ConfigOptions {
  ConfigOptions(..options, api_key: Some(api_key))
}

/// Set a custom base URL on configuration options
pub fn with_base_url(options: ConfigOptions, base_url: String) -> ConfigOptions {
  ConfigOptions(..options, base_url: Some(base_url))
}

/// Set a default model on configuration options
pub fn with_default_model(
  options: ConfigOptions,
  default_model: String,
) -> ConfigOptions {
  ConfigOptions(..options, default_model: Some(default_model))
}

/// Set a timeout override on configuration options
pub fn with_timeout_ms(options: ConfigOptions, timeout_ms: Int) -> ConfigOptions {
  ConfigOptions(..options, timeout_ms: Some(timeout_ms))
}

/// Set a retry override on configuration options
pub fn with_max_retries(
  options: ConfigOptions,
  max_retries: Int,
) -> ConfigOptions {
  ConfigOptions(..options, max_retries: Some(max_retries))
}

// =============================================================================
// Loading
// =============================================================================

/// Load configuration using explicit options first, then environment variables.
///
/// Sources of configuration (in order of precedence):
/// 1. Explicit options passed to the client
/// 2. Environment variables (ANTHROPIC_API_KEY)
pub fn load_config(options: ConfigOptions) -> Result(Config, AnthropicError) {
  let api_key =
    pick_api_key(options.api_key)
    |> result.map_error(fn(_) {
      config_error(
        "API key is required. Provide ConfigOptions.api_key or set ANTHROPIC_API_KEY.",
      )
    })

  api_key
  |> result.map(fn(key) {
    Config(
      api_key: key,
      base_url: choose_string(options.base_url, default_base_url),
      default_model: normalise_string_option(options.default_model),
      timeout_ms: choose_int(options.timeout_ms, default_timeout_ms),
      max_retries: choose_int(options.max_retries, default_max_retries),
    )
  })
}

// =============================================================================
// Helpers
// =============================================================================

fn pick_api_key(provided: Option(String)) -> Result(String, Nil) {
  case normalise_string_option(provided) {
    Some(key) -> Ok(key)
    None -> load_env_api_key()
  }
}

fn load_env_api_key() -> Result(String, Nil) {
  let value = getenv("ANTHROPIC_API_KEY", "")

  case normalise_string_option(Some(value)) {
    Some(key) -> Ok(key)
    None -> Error(Nil)
  }
}

fn normalise_string_option(value: Option(String)) -> Option(String) {
  case value {
    Some(str) -> {
      let trimmed = string.trim(str)
      case string.length(trimmed) {
        0 -> None
        _ -> Some(trimmed)
      }
    }
    None -> None
  }
}

@external(erlang, "os", "getenv")
fn ffi_getenv(
  variable: charlist.Charlist,
  default: charlist.Charlist,
) -> charlist.Charlist

fn getenv(variable: String, default: String) -> String {
  ffi_getenv(charlist.from_string(variable), charlist.from_string(default))
  |> charlist.to_string
}

fn choose_string(value: Option(String), default: String) -> String {
  case normalise_string_option(value) {
    Some(str) -> str
    None -> default
  }
}

fn choose_int(value: Option(Int), default: Int) -> Int {
  case value {
    Some(num) -> num
    None -> default
  }
}

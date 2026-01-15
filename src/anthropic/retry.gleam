//// Retry logic with exponential backoff for transient failures
////
//// This module provides automatic retry functionality for API requests
//// that encounter transient errors like rate limits, server overload, or timeouts.
////
//// ## Features
////
//// - Exponential backoff with configurable base delay
//// - Jitter to prevent thundering herd
//// - Configurable max retries
//// - Respects retry-after headers when available
////
//// ## Example
////
//// ```gleam
//// let retry_config = default_retry_config()
////   |> with_max_retries(5)
////   |> with_base_delay_ms(500)
////
//// let result = retry_with_backoff(retry_config, fn() {
////   api.create_message(client, request)
//// })
//// ```

import anthropic/types/error.{type AnthropicError, is_retryable}
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}

// =============================================================================
// Configuration Types
// =============================================================================

/// Configuration for retry behavior
pub type RetryConfig {
  RetryConfig(
    /// Maximum number of retry attempts (0 = no retries)
    max_retries: Int,
    /// Base delay in milliseconds for exponential backoff
    base_delay_ms: Int,
    /// Maximum delay in milliseconds (cap for exponential growth)
    max_delay_ms: Int,
    /// Jitter factor (0.0 to 1.0) - adds randomness to prevent thundering herd
    jitter_factor: Float,
    /// Multiplier for exponential backoff (typically 2.0)
    backoff_multiplier: Float,
  )
}

/// Result of a retry operation with metadata
pub type RetryResult(a) {
  RetryResult(
    /// The final result (success or last error)
    result: Result(a, AnthropicError),
    /// Number of attempts made
    attempts: Int,
    /// Total time spent on retries in milliseconds
    total_delay_ms: Int,
  )
}

// =============================================================================
// Default Configuration
// =============================================================================

/// Create a default retry configuration
///
/// Defaults:
/// - max_retries: 3
/// - base_delay_ms: 1000 (1 second)
/// - max_delay_ms: 60000 (60 seconds)
/// - jitter_factor: 0.25 (25% randomness)
/// - backoff_multiplier: 2.0
pub fn default_retry_config() -> RetryConfig {
  RetryConfig(
    max_retries: 3,
    base_delay_ms: 1000,
    max_delay_ms: 60_000,
    jitter_factor: 0.25,
    backoff_multiplier: 2.0,
  )
}

/// Create a retry configuration with no retries
pub fn no_retry_config() -> RetryConfig {
  RetryConfig(
    max_retries: 0,
    base_delay_ms: 0,
    max_delay_ms: 0,
    jitter_factor: 0.0,
    backoff_multiplier: 1.0,
  )
}

/// Create an aggressive retry configuration for high availability
pub fn aggressive_retry_config() -> RetryConfig {
  RetryConfig(
    max_retries: 5,
    base_delay_ms: 500,
    max_delay_ms: 30_000,
    jitter_factor: 0.5,
    backoff_multiplier: 2.0,
  )
}

// =============================================================================
// Configuration Builders
// =============================================================================

/// Set the maximum number of retries
pub fn with_max_retries(config: RetryConfig, max_retries: Int) -> RetryConfig {
  RetryConfig(..config, max_retries: int.max(0, max_retries))
}

/// Set the base delay in milliseconds
pub fn with_base_delay_ms(
  config: RetryConfig,
  base_delay_ms: Int,
) -> RetryConfig {
  RetryConfig(..config, base_delay_ms: int.max(0, base_delay_ms))
}

/// Set the maximum delay in milliseconds
pub fn with_max_delay_ms(config: RetryConfig, max_delay_ms: Int) -> RetryConfig {
  RetryConfig(..config, max_delay_ms: int.max(0, max_delay_ms))
}

/// Set the jitter factor (0.0 to 1.0)
pub fn with_jitter_factor(
  config: RetryConfig,
  jitter_factor: Float,
) -> RetryConfig {
  let clamped = float.min(1.0, float.max(0.0, jitter_factor))
  RetryConfig(..config, jitter_factor: clamped)
}

/// Set the backoff multiplier
pub fn with_backoff_multiplier(
  config: RetryConfig,
  multiplier: Float,
) -> RetryConfig {
  RetryConfig(..config, backoff_multiplier: float.max(1.0, multiplier))
}

// =============================================================================
// Delay Calculation
// =============================================================================

/// Calculate delay for a given attempt number (0-indexed)
pub fn calculate_delay(config: RetryConfig, attempt: Int) -> Int {
  // Exponential backoff: base_delay * (multiplier ^ attempt)
  let base = int.to_float(config.base_delay_ms)
  let exponential =
    base *. pow(config.backoff_multiplier, int.to_float(attempt))

  // Apply max delay cap
  let capped = float.min(exponential, int.to_float(config.max_delay_ms))

  // Apply jitter
  let jitter_range = capped *. config.jitter_factor
  let jitter = random_float() *. jitter_range *. 2.0 -. jitter_range
  let with_jitter = capped +. jitter

  // Ensure non-negative and convert to int
  float.truncate(float.max(0.0, with_jitter))
}

/// Calculate delay with optional retry-after header value
pub fn calculate_delay_with_retry_after(
  config: RetryConfig,
  attempt: Int,
  retry_after_ms: Option(Int),
) -> Int {
  let calculated = calculate_delay(config, attempt)

  case retry_after_ms {
    Some(retry_after) -> int.max(calculated, retry_after)
    None -> calculated
  }
}

// =============================================================================
// Retry Execution
// =============================================================================

/// Execute a function with retry logic
///
/// Returns the first successful result, or the last error after all retries
/// are exhausted.
pub fn retry_with_backoff(
  config: RetryConfig,
  operation: fn() -> Result(a, AnthropicError),
) -> RetryResult(a) {
  retry_loop(config, operation, 0, 0)
}

/// Internal retry loop
fn retry_loop(
  config: RetryConfig,
  operation: fn() -> Result(a, AnthropicError),
  attempt: Int,
  total_delay: Int,
) -> RetryResult(a) {
  let result = operation()

  case result {
    Ok(_) ->
      RetryResult(
        result: result,
        attempts: attempt + 1,
        total_delay_ms: total_delay,
      )

    Error(err) -> {
      // Check if we should retry
      let should_retry =
        attempt < config.max_retries
        && is_retryable(err)
        && config.max_retries > 0

      case should_retry {
        True -> {
          // Calculate delay and sleep
          let delay = calculate_delay(config, attempt)
          sleep_ms(delay)

          // Retry
          retry_loop(config, operation, attempt + 1, total_delay + delay)
        }
        False ->
          // Return final result
          RetryResult(
            result: result,
            attempts: attempt + 1,
            total_delay_ms: total_delay,
          )
      }
    }
  }
}

/// Execute with retry and return just the result
pub fn retry(
  config: RetryConfig,
  operation: fn() -> Result(a, AnthropicError),
) -> Result(a, AnthropicError) {
  let RetryResult(result: result, ..) = retry_with_backoff(config, operation)
  result
}

// =============================================================================
// Retry Predicates
// =============================================================================

/// Check if an error should be retried based on custom logic
pub fn should_retry_error(error: AnthropicError) -> Bool {
  is_retryable(error)
}

/// Get suggested retry delay from an error (if available)
pub fn get_retry_after_from_error(_error: AnthropicError) -> Option(Int) {
  // In a full implementation, this would parse retry-after headers
  // For now, return None to use calculated backoff
  None
}

// =============================================================================
// Utilities
// =============================================================================

/// Check if retry configuration allows retries
pub fn retries_enabled(config: RetryConfig) -> Bool {
  config.max_retries > 0
}

/// Get the maximum possible delay for a configuration
pub fn max_total_delay(config: RetryConfig) -> Int {
  // Sum of delays for all retry attempts
  calculate_max_total_delay(config, 0, 0)
}

fn calculate_max_total_delay(
  config: RetryConfig,
  attempt: Int,
  total: Int,
) -> Int {
  case attempt >= config.max_retries {
    True -> total
    False -> {
      let delay = calculate_delay(config, attempt)
      calculate_max_total_delay(config, attempt + 1, total + delay)
    }
  }
}

// =============================================================================
// FFI Helpers
// =============================================================================

/// Sleep for the specified number of milliseconds
@external(erlang, "timer", "sleep")
fn sleep_ms(ms: Int) -> Nil

/// Generate a random float between 0.0 and 1.0
@external(erlang, "rand", "uniform")
fn random_float() -> Float

/// Simple power function for exponential backoff
fn pow(base: Float, exponent: Float) -> Float {
  case exponent <=. 0.0 {
    True -> 1.0
    False -> pow_loop(base, float.truncate(exponent), 1.0)
  }
}

fn pow_loop(base: Float, n: Int, acc: Float) -> Float {
  case n <= 0 {
    True -> acc
    False -> pow_loop(base, n - 1, acc *. base)
  }
}

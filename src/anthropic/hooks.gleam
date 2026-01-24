//// Logging and telemetry hooks for observability
////
//// This module provides optional hooks for monitoring API interactions,
//// including request lifecycle events, errors, and streaming events.
////
//// ## Hook Points
////
//// - `on_request_start`: Called before sending a request
//// - `on_request_end`: Called after receiving a response (success or error)
//// - `on_retry`: Called before each retry attempt
//// - `on_stream_event`: Called for each streaming event
////
//// ## Example
////
//// ```gleam
//// let hooks = default_hooks()
////   |> with_on_request_start(fn(event) {
////     io.println("Starting request to " <> event.endpoint)
////   })
////   |> with_on_request_end(fn(event) {
////     io.println("Request completed in " <> int.to_string(event.duration_ms) <> "ms")
////   })
////
//// let client = new_client_with_hooks(config, hooks)
//// ```

import anthropic/error.{type AnthropicError}
import anthropic/request.{type CreateMessageRequest, type CreateMessageResponse}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

// =============================================================================
// Event Types
// =============================================================================

/// Event emitted when a request starts
pub type RequestStartEvent {
  RequestStartEvent(
    /// API endpoint being called
    endpoint: String,
    /// Request being sent (without sensitive data)
    request: RequestSummary,
    /// Timestamp when request started (milliseconds since epoch)
    timestamp_ms: Int,
    /// Unique request ID for correlation
    request_id: String,
  )
}

/// Event emitted when a request ends
pub type RequestEndEvent {
  RequestEndEvent(
    /// API endpoint that was called
    endpoint: String,
    /// Duration of the request in milliseconds
    duration_ms: Int,
    /// Whether the request succeeded
    success: Bool,
    /// Response summary (if successful)
    response: Option(ResponseSummary),
    /// Error (if failed)
    error: Option(AnthropicError),
    /// Unique request ID for correlation
    request_id: String,
    /// Number of retry attempts made
    retry_count: Int,
  )
}

/// Event emitted before a retry attempt
pub type RetryEvent {
  RetryEvent(
    /// API endpoint being retried
    endpoint: String,
    /// Current retry attempt (1-indexed)
    attempt: Int,
    /// Maximum retry attempts configured
    max_attempts: Int,
    /// Delay before this retry in milliseconds
    delay_ms: Int,
    /// Error that triggered the retry
    error: AnthropicError,
    /// Unique request ID for correlation
    request_id: String,
  )
}

/// Event emitted for streaming events
pub type StreamEvent {
  StreamEvent(
    /// Type of stream event
    event_type: StreamEventType,
    /// Unique request ID for correlation
    request_id: String,
    /// Timestamp of the event
    timestamp_ms: Int,
  )
}

/// Types of streaming events
pub type StreamEventType {
  /// Stream connection opened
  StreamOpened
  /// Message start event received
  MessageStart
  /// Content block start event received
  ContentBlockStart(index: Int)
  /// Content block delta event received
  ContentBlockDelta(index: Int, delta_type: String)
  /// Content block stop event received
  ContentBlockStop(index: Int)
  /// Message delta event received
  MessageDelta
  /// Message stop event received
  MessageStop
  /// Stream connection closed
  StreamClosed
  /// Stream error occurred
  StreamError(error: String)
}

// =============================================================================
// Summary Types (for logging without sensitive data)
// =============================================================================

/// Summary of a request (without API key or full content)
pub type RequestSummary {
  RequestSummary(
    /// Model being used
    model: String,
    /// Number of messages in the request
    message_count: Int,
    /// max_tokens setting
    max_tokens: Int,
    /// Whether streaming is enabled
    stream: Bool,
    /// Number of tools defined
    tool_count: Int,
    /// Whether a system prompt is set
    has_system: Bool,
  )
}

/// Summary of a response
pub type ResponseSummary {
  ResponseSummary(
    /// Response ID
    id: String,
    /// Model that generated the response
    model: String,
    /// Stop reason
    stop_reason: Option(String),
    /// Input tokens used
    input_tokens: Int,
    /// Output tokens generated
    output_tokens: Int,
    /// Number of content blocks
    content_block_count: Int,
  )
}

/// Create a request summary from a CreateMessageRequest
pub fn summarize_request(request: CreateMessageRequest) -> RequestSummary {
  RequestSummary(
    model: request.model,
    message_count: count_messages(request.messages),
    max_tokens: request.max_tokens,
    stream: option.unwrap(request.stream, False),
    tool_count: count_tools(request.tools),
    has_system: option.is_some(request.system),
  )
}

/// Create a response summary from a CreateMessageResponse
pub fn summarize_response(response: CreateMessageResponse) -> ResponseSummary {
  ResponseSummary(
    id: response.id,
    model: response.model,
    stop_reason: option.map(response.stop_reason, request.stop_reason_to_string),
    input_tokens: response.usage.input_tokens,
    output_tokens: response.usage.output_tokens,
    content_block_count: count_content_blocks(response.content),
  )
}

// Helper functions for counting
fn count_messages(messages: List(a)) -> Int {
  list.length(messages)
}

fn count_tools(tools: Option(List(a))) -> Int {
  case tools {
    Some(t) -> list.length(t)
    None -> 0
  }
}

fn count_content_blocks(blocks: List(a)) -> Int {
  list.length(blocks)
}

// =============================================================================
// Hook Configuration
// =============================================================================

/// Configuration for logging/telemetry hooks
pub type Hooks {
  Hooks(
    /// Called when a request starts
    on_request_start: Option(fn(RequestStartEvent) -> Nil),
    /// Called when a request ends (success or failure)
    on_request_end: Option(fn(RequestEndEvent) -> Nil),
    /// Called before each retry attempt
    on_retry: Option(fn(RetryEvent) -> Nil),
    /// Called for each streaming event
    on_stream_event: Option(fn(StreamEvent) -> Nil),
  )
}

/// Create default hooks (all disabled)
pub fn default_hooks() -> Hooks {
  Hooks(
    on_request_start: None,
    on_request_end: None,
    on_retry: None,
    on_stream_event: None,
  )
}

/// Create hooks with no callbacks (alias for default_hooks)
pub fn no_hooks() -> Hooks {
  default_hooks()
}

// =============================================================================
// Hook Builders
// =============================================================================

/// Set the on_request_start hook
pub fn with_on_request_start(
  hooks: Hooks,
  callback: fn(RequestStartEvent) -> Nil,
) -> Hooks {
  Hooks(..hooks, on_request_start: Some(callback))
}

/// Set the on_request_end hook
pub fn with_on_request_end(
  hooks: Hooks,
  callback: fn(RequestEndEvent) -> Nil,
) -> Hooks {
  Hooks(..hooks, on_request_end: Some(callback))
}

/// Set the on_retry hook
pub fn with_on_retry(hooks: Hooks, callback: fn(RetryEvent) -> Nil) -> Hooks {
  Hooks(..hooks, on_retry: Some(callback))
}

/// Set the on_stream_event hook
pub fn with_on_stream_event(
  hooks: Hooks,
  callback: fn(StreamEvent) -> Nil,
) -> Hooks {
  Hooks(..hooks, on_stream_event: Some(callback))
}

// =============================================================================
// Hook Invocation
// =============================================================================

/// Emit a request start event
pub fn emit_request_start(hooks: Hooks, event: RequestStartEvent) -> Nil {
  case hooks.on_request_start {
    Some(callback) -> callback(event)
    None -> Nil
  }
}

/// Emit a request end event
pub fn emit_request_end(hooks: Hooks, event: RequestEndEvent) -> Nil {
  case hooks.on_request_end {
    Some(callback) -> callback(event)
    None -> Nil
  }
}

/// Emit a retry event
pub fn emit_retry(hooks: Hooks, event: RetryEvent) -> Nil {
  case hooks.on_retry {
    Some(callback) -> callback(event)
    None -> Nil
  }
}

/// Emit a stream event
pub fn emit_stream_event(hooks: Hooks, event: StreamEvent) -> Nil {
  case hooks.on_stream_event {
    Some(callback) -> callback(event)
    None -> Nil
  }
}

// =============================================================================
// Pre-built Hook Implementations
// =============================================================================

/// Create a simple logging hook that prints to stdout
pub fn simple_logging_hooks() -> Hooks {
  default_hooks()
  |> with_on_request_start(fn(event) {
    log_message(
      "REQUEST_START",
      "endpoint="
        <> event.endpoint
        <> " model="
        <> event.request.model
        <> " messages="
        <> int.to_string(event.request.message_count)
        <> " request_id="
        <> event.request_id,
    )
  })
  |> with_on_request_end(fn(event) {
    case event.success {
      True ->
        log_message(
          "REQUEST_END",
          "endpoint="
            <> event.endpoint
            <> " duration_ms="
            <> int.to_string(event.duration_ms)
            <> " success=true request_id="
            <> event.request_id,
        )
      False ->
        log_message(
          "REQUEST_END",
          "endpoint="
            <> event.endpoint
            <> " duration_ms="
            <> int.to_string(event.duration_ms)
            <> " success=false request_id="
            <> event.request_id,
        )
    }
  })
  |> with_on_retry(fn(event) {
    log_message(
      "RETRY",
      "endpoint="
        <> event.endpoint
        <> " attempt="
        <> int.to_string(event.attempt)
        <> "/"
        <> int.to_string(event.max_attempts)
        <> " delay_ms="
        <> int.to_string(event.delay_ms)
        <> " request_id="
        <> event.request_id,
    )
  })
}

/// Create a metrics-focused hook (counts and timings only)
pub fn metrics_hooks(on_metric: fn(String, Int) -> Nil) -> Hooks {
  default_hooks()
  |> with_on_request_end(fn(event) {
    on_metric("request_duration_ms", event.duration_ms)
    case event.success {
      True -> on_metric("request_success", 1)
      False -> on_metric("request_failure", 1)
    }
    on_metric("retry_count", event.retry_count)

    case event.response {
      Some(resp) -> {
        on_metric("input_tokens", resp.input_tokens)
        on_metric("output_tokens", resp.output_tokens)
      }
      None -> Nil
    }
  })
}

// =============================================================================
// Utility Functions
// =============================================================================

/// Generate a unique request ID
pub fn generate_request_id() -> String {
  // Simple implementation using timestamp and random
  let timestamp = get_timestamp_ms()
  let random = random_int(0, 999_999)
  "req_" <> int.to_string(timestamp) <> "_" <> int.to_string(random)
}

/// Get current timestamp in milliseconds
@external(erlang, "os", "system_time")
fn system_time_native() -> Int

fn get_timestamp_ms() -> Int {
  // Convert to milliseconds (erlang returns microseconds by default)
  system_time_native() / 1000
}

/// Generate a random integer in range
@external(erlang, "rand", "uniform")
fn random_uniform(max: Int) -> Int

fn random_int(min: Int, max: Int) -> Int {
  min + random_uniform(max - min)
}

/// Simple logging function
fn log_message(level: String, message: String) -> Nil {
  io_format("[~s] ~s~n", [level, message])
}

@external(erlang, "io", "format")
fn io_format(format: String, args: List(String)) -> Nil

// =============================================================================
// Hook Composition
// =============================================================================

/// Combine two hooks, running both callbacks when events occur
pub fn combine_hooks(first: Hooks, second: Hooks) -> Hooks {
  Hooks(
    on_request_start: combine_callbacks(
      first.on_request_start,
      second.on_request_start,
    ),
    on_request_end: combine_callbacks(
      first.on_request_end,
      second.on_request_end,
    ),
    on_retry: combine_callbacks(first.on_retry, second.on_retry),
    on_stream_event: combine_callbacks(
      first.on_stream_event,
      second.on_stream_event,
    ),
  )
}

fn combine_callbacks(
  first: Option(fn(a) -> Nil),
  second: Option(fn(a) -> Nil),
) -> Option(fn(a) -> Nil) {
  case first, second {
    None, None -> None
    Some(f), None -> Some(f)
    None, Some(s) -> Some(s)
    Some(f), Some(s) ->
      Some(fn(event) {
        f(event)
        s(event)
      })
  }
}

/// Check if any hooks are configured
pub fn has_hooks(hooks: Hooks) -> Bool {
  option.is_some(hooks.on_request_start)
  || option.is_some(hooks.on_request_end)
  || option.is_some(hooks.on_retry)
  || option.is_some(hooks.on_stream_event)
}

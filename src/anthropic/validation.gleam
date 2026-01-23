//// Request validation for Anthropic API
////
//// This module provides comprehensive validation for API requests before
//// they are sent, catching common errors early and providing helpful messages.
////
//// ## Validation Checks
////
//// - Non-empty messages list
//// - Valid model name format
//// - max_tokens within bounds (1 to 4096 for most models)
//// - Valid temperature range (0.0 to 1.0)
//// - Valid top_p range (0.0 to 1.0)
//// - Valid top_k (positive integer)
//// - Tool definition validation
////
//// ## Example
////
//// ```gleam
//// let request = create_request("claude-sonnet-4-20250514", messages, 1024)
////
//// case validate_request(request) {
////   Ok(_) -> api.create_message(client, request)
////   Error(errors) -> {
////     io.println("Validation failed:")
////     list.each(errors, fn(e) { io.println("  - " <> e.message) })
////   }
//// }
//// ```

import anthropic/types/error.{type AnthropicError}
import anthropic/types/message.{type ContentBlock, type Message, TextBlock}
import anthropic/types/request.{type CreateMessageRequest}
import anthropic/types/tool.{type Tool}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// Validation Error Types
// =============================================================================

/// Field that failed validation
pub type ValidationField {
  MessagesField
  ModelField
  MaxTokensField
  TemperatureField
  TopPField
  TopKField
  SystemField
  StopSequencesField
  ToolsField
  ToolChoiceField
}

/// Convert a ValidationField to a string
pub fn field_to_string(field: ValidationField) -> String {
  case field {
    MessagesField -> "messages"
    ModelField -> "model"
    MaxTokensField -> "max_tokens"
    TemperatureField -> "temperature"
    TopPField -> "top_p"
    TopKField -> "top_k"
    SystemField -> "system"
    StopSequencesField -> "stop_sequences"
    ToolsField -> "tools"
    ToolChoiceField -> "tool_choice"
  }
}

/// A single validation error
pub type ValidationError {
  ValidationError(
    /// The field that failed validation
    field: ValidationField,
    /// Human-readable error message
    message: String,
    /// Optional value that caused the error
    value: Option(String),
  )
}

/// Create a validation error
pub fn validation_error(
  field: ValidationField,
  message: String,
) -> ValidationError {
  ValidationError(field: field, message: message, value: None)
}

/// Create a validation error with value context
pub fn validation_error_with_value(
  field: ValidationField,
  message: String,
  value: String,
) -> ValidationError {
  ValidationError(field: field, message: message, value: Some(value))
}

/// Convert a ValidationError to a string
pub fn error_to_string(error: ValidationError) -> String {
  let base = field_to_string(error.field) <> ": " <> error.message

  case error.value {
    Some(v) -> base <> " (got: " <> v <> ")"
    None -> base
  }
}

/// Convert a list of validation errors to a combined string
pub fn errors_to_string(errors: List(ValidationError)) -> String {
  errors
  |> list.map(error_to_string)
  |> string.join("; ")
}

// =============================================================================
// Validation Limits
// =============================================================================

/// Model-specific token limits
pub type ModelLimits {
  ModelLimits(
    /// Minimum max_tokens value
    min_tokens: Int,
    /// Maximum max_tokens value
    max_tokens: Int,
    /// Maximum context window
    context_window: Int,
  )
}

/// Get limits for a model
pub fn get_model_limits(model: String) -> ModelLimits {
  // Default limits for Claude 3.x and newer models
  case string.contains(model, "claude-3-opus") {
    True ->
      ModelLimits(min_tokens: 1, max_tokens: 4096, context_window: 200_000)
    False ->
      case
        string.contains(model, "claude-3-sonnet")
        || string.contains(model, "claude-sonnet")
      {
        True ->
          ModelLimits(min_tokens: 1, max_tokens: 8192, context_window: 200_000)
        False ->
          case
            string.contains(model, "claude-3-haiku")
            || string.contains(model, "claude-3-5-haiku")
          {
            True ->
              ModelLimits(
                min_tokens: 1,
                max_tokens: 8192,
                context_window: 200_000,
              )
            False ->
              // Default limits
              ModelLimits(
                min_tokens: 1,
                max_tokens: 8192,
                context_window: 200_000,
              )
          }
      }
  }
}

// =============================================================================
// Individual Validators
// =============================================================================

/// Validate the messages list
pub fn validate_messages(
  messages: List(Message),
) -> Result(Nil, List(ValidationError)) {
  let errors = []

  // Check for empty messages
  let errors = case list.is_empty(messages) {
    True -> [
      validation_error(MessagesField, "messages list cannot be empty"),
      ..errors
    ]
    False -> errors
  }

  // Check for empty content in messages
  let errors =
    list.index_fold(messages, errors, fn(acc, msg, idx) {
      case list.is_empty(msg.content) {
        True -> [
          validation_error_with_value(
            MessagesField,
            "message content cannot be empty",
            "message[" <> int.to_string(idx) <> "]",
          ),
          ..acc
        ]
        False -> acc
      }
    })

  // Check for valid alternating pattern (user/assistant)
  let errors = case validate_message_alternation(messages) {
    Ok(_) -> errors
    Error(err) -> [err, ..errors]
  }

  case errors {
    [] -> Ok(Nil)
    errs -> Error(list.reverse(errs))
  }
}

/// Validate that messages alternate correctly
fn validate_message_alternation(
  messages: List(Message),
) -> Result(Nil, ValidationError) {
  case messages {
    [] -> Ok(Nil)
    [first, ..] ->
      case first.role {
        message.User -> check_alternation(messages, message.User)
        message.Assistant ->
          Error(validation_error(
            MessagesField,
            "conversation must start with a user message",
          ))
      }
  }
}

fn check_alternation(
  messages: List(Message),
  expected_role: message.Role,
) -> Result(Nil, ValidationError) {
  case messages {
    [] -> Ok(Nil)
    [msg, ..rest] ->
      case msg.role == expected_role {
        True -> {
          let next_role = case expected_role {
            message.User -> message.Assistant
            message.Assistant -> message.User
          }
          check_alternation(rest, next_role)
        }
        False ->
          Error(validation_error(
            MessagesField,
            "messages must alternate between user and assistant roles",
          ))
      }
  }
}

/// Validate the model name
pub fn validate_model(model: String) -> Result(Nil, List(ValidationError)) {
  let trimmed = string.trim(model)
  let errors = []

  // Check for empty model
  let errors = case string.is_empty(trimmed) {
    True -> [
      validation_error(ModelField, "model name cannot be empty"),
      ..errors
    ]
    False -> errors
  }

  // Check model name format (alphanumeric, hyphens, periods)
  let errors = case string.is_empty(trimmed) {
    True -> errors
    False ->
      case is_valid_model_name(trimmed) {
        True -> errors
        False -> [
          validation_error_with_value(
            ModelField,
            "model name contains invalid characters",
            trimmed,
          ),
          ..errors
        ]
      }
  }

  case errors {
    [] -> Ok(Nil)
    errs -> Error(list.reverse(errs))
  }
}

/// Check if a model name has valid format
fn is_valid_model_name(name: String) -> Bool {
  // Valid model names: alphanumeric, hyphens, periods, underscores
  name
  |> string.to_graphemes
  |> list.all(fn(char) {
    is_alphanumeric(char) || char == "." || char == "-" || char == "_"
  })
}

fn is_alphanumeric(char: String) -> Bool {
  case string.to_utf_codepoints(char) {
    [codepoint] -> {
      let code = string.utf_codepoint_to_int(codepoint)
      // a-z: 97-122, A-Z: 65-90, 0-9: 48-57
      { code >= 97 && code <= 122 }
      || { code >= 65 && code <= 90 }
      || { code >= 48 && code <= 57 }
    }
    _ -> False
  }
}

/// Validate max_tokens
pub fn validate_max_tokens(
  max_tokens: Int,
  model: String,
) -> Result(Nil, List(ValidationError)) {
  let limits = get_model_limits(model)
  let errors = []

  let errors = case max_tokens < limits.min_tokens {
    True -> [
      validation_error_with_value(
        MaxTokensField,
        "max_tokens must be at least " <> int.to_string(limits.min_tokens),
        int.to_string(max_tokens),
      ),
      ..errors
    ]
    False -> errors
  }

  let errors = case max_tokens > limits.max_tokens {
    True -> [
      validation_error_with_value(
        MaxTokensField,
        "max_tokens cannot exceed " <> int.to_string(limits.max_tokens),
        int.to_string(max_tokens),
      ),
      ..errors
    ]
    False -> errors
  }

  case errors {
    [] -> Ok(Nil)
    errs -> Error(list.reverse(errs))
  }
}

/// Validate temperature
pub fn validate_temperature(
  temperature: Option(Float),
) -> Result(Nil, List(ValidationError)) {
  case temperature {
    None -> Ok(Nil)
    Some(t) ->
      case t >=. 0.0 && t <=. 1.0 {
        True -> Ok(Nil)
        False ->
          Error([
            validation_error_with_value(
              TemperatureField,
              "temperature must be between 0.0 and 1.0",
              float.to_string(t),
            ),
          ])
      }
  }
}

/// Validate top_p
pub fn validate_top_p(
  top_p: Option(Float),
) -> Result(Nil, List(ValidationError)) {
  case top_p {
    None -> Ok(Nil)
    Some(p) ->
      case p >=. 0.0 && p <=. 1.0 {
        True -> Ok(Nil)
        False ->
          Error([
            validation_error_with_value(
              TopPField,
              "top_p must be between 0.0 and 1.0",
              float.to_string(p),
            ),
          ])
      }
  }
}

/// Validate top_k
pub fn validate_top_k(top_k: Option(Int)) -> Result(Nil, List(ValidationError)) {
  case top_k {
    None -> Ok(Nil)
    Some(k) ->
      case k > 0 {
        True -> Ok(Nil)
        False ->
          Error([
            validation_error_with_value(
              TopKField,
              "top_k must be a positive integer",
              int.to_string(k),
            ),
          ])
      }
  }
}

/// Validate system prompt
pub fn validate_system(
  system: Option(String),
) -> Result(Nil, List(ValidationError)) {
  case system {
    None -> Ok(Nil)
    Some(s) ->
      case string.is_empty(string.trim(s)) {
        True ->
          Error([
            validation_error(
              SystemField,
              "system prompt cannot be empty when provided",
            ),
          ])
        False -> Ok(Nil)
      }
  }
}

/// Validate stop sequences
pub fn validate_stop_sequences(
  sequences: Option(List(String)),
) -> Result(Nil, List(ValidationError)) {
  case sequences {
    None -> Ok(Nil)
    Some(seqs) -> {
      let errors =
        seqs
        |> list.index_fold([], fn(acc, seq, idx) {
          case string.is_empty(seq) {
            True -> [
              validation_error_with_value(
                StopSequencesField,
                "stop sequence cannot be empty",
                "stop_sequences[" <> int.to_string(idx) <> "]",
              ),
              ..acc
            ]
            False -> acc
          }
        })

      case errors {
        [] -> Ok(Nil)
        errs -> Error(list.reverse(errs))
      }
    }
  }
}

/// Validate tool definitions
pub fn validate_tools(
  tools: Option(List(Tool)),
) -> Result(Nil, List(ValidationError)) {
  case tools {
    None -> Ok(Nil)
    Some(tool_list) -> {
      let errors =
        tool_list
        |> list.index_fold([], fn(acc, t, idx) {
          validate_single_tool(t, idx)
          |> list.append(acc)
        })

      case errors {
        [] -> Ok(Nil)
        errs -> Error(list.reverse(errs))
      }
    }
  }
}

/// Validate a single tool definition
///
/// Note: Since ToolName is now an opaque type that validates at construction,
/// tool name validation is guaranteed by the type system. This function is
/// kept for potential future validation of other tool properties.
fn validate_single_tool(_t: Tool, _index: Int) -> List(ValidationError) {
  // Tool names are now validated at construction time via the opaque ToolName type.
  // The type system guarantees that any Tool has a valid name.
  // Additional tool validation could be added here in the future.
  []
}

// =============================================================================
// Complete Request Validation
// =============================================================================

/// Validate a complete CreateMessageRequest
///
/// Returns Ok(Nil) if the request is valid, or Error with a list of all
/// validation errors found.
pub fn validate_request(
  request: CreateMessageRequest,
) -> Result(Nil, List(ValidationError)) {
  // Collect all validation errors
  let errors =
    []
    |> collect_errors(validate_messages(request.messages))
    |> collect_errors(validate_model(request.model))
    |> collect_errors(validate_max_tokens(request.max_tokens, request.model))
    |> collect_errors(validate_temperature(request.temperature))
    |> collect_errors(validate_top_p(request.top_p))
    |> collect_errors(validate_top_k(request.top_k))
    |> collect_errors(validate_system(request.system))
    |> collect_errors(validate_stop_sequences(request.stop_sequences))
    |> collect_errors(validate_tools(request.tools))

  case errors {
    [] -> Ok(Nil)
    errs -> Error(list.reverse(errs))
  }
}

/// Helper to collect errors from a validation result
fn collect_errors(
  existing: List(ValidationError),
  result: Result(Nil, List(ValidationError)),
) -> List(ValidationError) {
  case result {
    Ok(_) -> existing
    Error(new_errors) -> list.append(new_errors, existing)
  }
}

// =============================================================================
// Quick Validation Helpers
// =============================================================================

/// Quick check if a request is valid (returns Bool)
pub fn is_valid(request: CreateMessageRequest) -> Bool {
  case validate_request(request) {
    Ok(_) -> True
    Error(_) -> False
  }
}

/// Validate a request and return an AnthropicError if invalid
pub fn validate_or_error(
  request: CreateMessageRequest,
) -> Result(CreateMessageRequest, AnthropicError) {
  case validate_request(request) {
    Ok(_) -> Ok(request)
    Error(errors) ->
      Error(error.invalid_request_error(
        "Request validation failed: " <> errors_to_string(errors),
      ))
  }
}

/// Validate a request and return Result(Nil, AnthropicError)
///
/// This is a convenience function for cases where you only need to know
/// if validation passed, not the request itself. Used internally by
/// `api.gleam` and `http.gleam`.
pub fn validate_request_or_error(
  request: CreateMessageRequest,
) -> Result(Nil, AnthropicError) {
  case validate_request(request) {
    Ok(_) -> Ok(Nil)
    Error(errors) ->
      Error(error.invalid_request_error(
        "Request validation failed: " <> errors_to_string(errors),
      ))
  }
}

// =============================================================================
// Content Validation
// =============================================================================

/// Validate that content blocks are non-empty
pub fn validate_content_blocks(
  blocks: List(ContentBlock),
) -> Result(Nil, List(ValidationError)) {
  case list.is_empty(blocks) {
    True ->
      Error([validation_error(MessagesField, "content blocks cannot be empty")])
    False -> {
      let errors =
        blocks
        |> list.index_fold([], fn(acc, block, idx) {
          case block {
            TextBlock(text: text) ->
              case string.is_empty(string.trim(text)) {
                True -> [
                  validation_error_with_value(
                    MessagesField,
                    "text content cannot be empty",
                    "content[" <> int.to_string(idx) <> "]",
                  ),
                  ..acc
                ]
                False -> acc
              }
            _ -> acc
          }
        })

      case errors {
        [] -> Ok(Nil)
        errs -> Error(list.reverse(errs))
      }
    }
  }
}

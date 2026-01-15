//// Core message types for the Anthropic Messages API
////
//// This module defines the fundamental types for working with Claude's API,
//// including messages, content blocks, and their JSON serialization.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// =============================================================================
// Role
// =============================================================================

/// Role of a message in a conversation
pub type Role {
  /// Message from the user
  User
  /// Message from the assistant (Claude)
  Assistant
}

/// Encode a Role to JSON string value
pub fn role_to_json(role: Role) -> Json {
  case role {
    User -> json.string("user")
    Assistant -> json.string("assistant")
  }
}

/// Convert a string to Role
pub fn role_from_string(str: String) -> Result(Role, String) {
  case str {
    "user" -> Ok(User)
    "assistant" -> Ok(Assistant)
    _ -> Error("Invalid role: " <> str)
  }
}

/// Convert a Role to string
pub fn role_to_string(role: Role) -> String {
  case role {
    User -> "user"
    Assistant -> "assistant"
  }
}

// =============================================================================
// ImageSource
// =============================================================================

/// Source type for images
pub type ImageSourceType {
  /// Base64 encoded image data
  Base64
}

/// Image source for image content blocks
pub type ImageSource {
  ImageSource(
    /// Type of image source (currently only base64)
    source_type: ImageSourceType,
    /// MIME type of the image (e.g., "image/jpeg", "image/png", "image/gif", "image/webp")
    media_type: String,
    /// Base64 encoded image data
    data: String,
  )
}

/// Encode an ImageSource to JSON
pub fn image_source_to_json(source: ImageSource) -> Json {
  let ImageSource(source_type: _, media_type: media_type, data: data) = source
  json.object([
    #("type", json.string("base64")),
    #("media_type", json.string(media_type)),
    #("data", json.string(data)),
  ])
}

/// Create an ImageSource from a dict (for JSON decoding)
pub fn image_source_from_dict(
  dict: Dict(String, String),
) -> Result(ImageSource, String) {
  use media_type <- result.try(
    dict.get(dict, "media_type")
    |> result.replace_error("Missing media_type field"),
  )
  use data <- result.try(
    dict.get(dict, "data")
    |> result.replace_error("Missing data field"),
  )
  Ok(ImageSource(source_type: Base64, media_type: media_type, data: data))
}

// =============================================================================
// ContentBlock
// =============================================================================

/// Content block in a message - represents different types of content
pub type ContentBlock {
  /// Plain text content
  TextBlock(text: String)
  /// Image content with source data
  ImageBlock(source: ImageSource)
  /// Tool use request from the assistant
  ToolUseBlock(
    /// Unique identifier for this tool use
    id: String,
    /// Name of the tool being called
    name: String,
    /// JSON string of input arguments for the tool
    input: String,
  )
  /// Result of a tool execution
  ToolResultBlock(
    /// ID of the tool use this is responding to
    tool_use_id: String,
    /// Content of the tool result (can be text or error)
    content: String,
    /// Whether this result represents an error
    is_error: Option(Bool),
  )
}

/// Encode a ContentBlock to JSON
pub fn content_block_to_json(block: ContentBlock) -> Json {
  case block {
    TextBlock(text: text) ->
      json.object([#("type", json.string("text")), #("text", json.string(text))])

    ImageBlock(source: source) ->
      json.object([
        #("type", json.string("image")),
        #("source", image_source_to_json(source)),
      ])

    ToolUseBlock(id: id, name: name, input: input) ->
      json.object([
        #("type", json.string("tool_use")),
        #("id", json.string(id)),
        #("name", json.string(name)),
        #("input", json_string_to_raw_json(input)),
      ])

    ToolResultBlock(
      tool_use_id: tool_use_id,
      content: content,
      is_error: is_error,
    ) -> {
      let base_fields = [
        #("type", json.string("tool_result")),
        #("tool_use_id", json.string(tool_use_id)),
        #("content", json.string(content)),
      ]
      let fields = case is_error {
        Some(True) -> list.append(base_fields, [#("is_error", json.bool(True))])
        Some(False) ->
          list.append(base_fields, [#("is_error", json.bool(False))])
        None -> base_fields
      }
      json.object(fields)
    }
  }
}

/// Get the type of a content block as a string
pub fn content_block_type(block: ContentBlock) -> String {
  case block {
    TextBlock(_) -> "text"
    ImageBlock(_) -> "image"
    ToolUseBlock(_, _, _) -> "tool_use"
    ToolResultBlock(_, _, _) -> "tool_result"
  }
}

// =============================================================================
// Message
// =============================================================================

/// A message in a conversation
pub type Message {
  Message(
    /// Role of the message sender
    role: Role,
    /// List of content blocks in the message
    content: List(ContentBlock),
  )
}

/// Encode a Message to JSON
pub fn message_to_json(message: Message) -> Json {
  let Message(role: role, content: content) = message
  json.object([
    #("role", role_to_json(role)),
    #("content", json.array(content, content_block_to_json)),
  ])
}

/// Encode a list of Messages to JSON
pub fn messages_to_json(messages: List(Message)) -> Json {
  json.array(messages, message_to_json)
}

/// Get the text content from a message (concatenated)
pub fn message_text(message: Message) -> String {
  message.content
  |> list.filter_map(fn(block) {
    case block {
      TextBlock(text: text) -> Ok(text)
      _ -> Error(Nil)
    }
  })
  |> string.join("")
}

/// Check if a message contains tool use blocks
pub fn has_tool_use(message: Message) -> Bool {
  list.any(message.content, fn(block) {
    case block {
      ToolUseBlock(_, _, _) -> True
      _ -> False
    }
  })
}

/// Get all tool use blocks from a message
pub fn get_tool_uses(message: Message) -> List(ContentBlock) {
  list.filter(message.content, fn(block) {
    case block {
      ToolUseBlock(_, _, _) -> True
      _ -> False
    }
  })
}

// =============================================================================
// Convenience constructors
// =============================================================================

/// Create a user message with text content
pub fn user_message(text_content: String) -> Message {
  Message(role: User, content: [TextBlock(text: text_content)])
}

/// Create an assistant message with text content
pub fn assistant_message(text_content: String) -> Message {
  Message(role: Assistant, content: [TextBlock(text: text_content)])
}

/// Create a message with the given role and content blocks
pub fn message(role: Role, content: List(ContentBlock)) -> Message {
  Message(role: role, content: content)
}

/// Create a text content block
pub fn text(content: String) -> ContentBlock {
  TextBlock(text: content)
}

/// Create an image content block from base64 data
pub fn image(media_type: String, base64_data: String) -> ContentBlock {
  ImageBlock(source: ImageSource(
    source_type: Base64,
    media_type: media_type,
    data: base64_data,
  ))
}

/// Create a tool use content block
pub fn tool_use(id: String, name: String, input: String) -> ContentBlock {
  ToolUseBlock(id: id, name: name, input: input)
}

/// Create a tool result content block
pub fn tool_result(tool_use_id: String, content: String) -> ContentBlock {
  ToolResultBlock(tool_use_id: tool_use_id, content: content, is_error: None)
}

/// Create a tool error result content block
pub fn tool_error(tool_use_id: String, error_message: String) -> ContentBlock {
  ToolResultBlock(
    tool_use_id: tool_use_id,
    content: error_message,
    is_error: Some(True),
  )
}

// =============================================================================
// Raw JSON helpers
// =============================================================================

/// Convert a JSON string to a raw JSON value (for embedding pre-encoded JSON)
/// Uses the FFI to parse JSON and convert Erlang terms to Gleam Json
fn json_string_to_raw_json(json_string: String) -> Json {
  ffi_json_string_to_gleam_json(json_string)
}

/// FFI function to parse JSON string and convert to Gleam Json type
@external(erlang, "anthropic_ffi", "json_string_to_gleam_json")
fn ffi_json_string_to_gleam_json(json_string: String) -> Json

// =============================================================================
// JSON String helpers
// =============================================================================

/// Convert a message to a JSON string
pub fn message_to_json_string(message: Message) -> String {
  message
  |> message_to_json
  |> json.to_string
}

/// Convert a content block to a JSON string
pub fn content_block_to_json_string(block: ContentBlock) -> String {
  block
  |> content_block_to_json
  |> json.to_string
}

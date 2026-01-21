//// Tool definition types for the Anthropic Messages API
////
//// This module defines types for tool definitions following the Anthropic schema.
//// Tools allow Claude to call external functions and receive results.
////
//// ## Example
////
//// ```gleam
//// import anthropic/types/tool.{tool_name, Tool, InputSchema}
//// import gleam/option.{None, Some}
////
//// let assert Ok(name) = tool_name("get_weather")
//// let weather_tool = Tool(
////   name: name,
////   description: Some("Get the current weather for a location"),
////   input_schema: InputSchema(
////     schema_type: "object",
////     properties: Some([
////       #("location", PropertySchema(
////         property_type: "string",
////         description: Some("City and state, e.g. 'San Francisco, CA'"),
////         enum_values: None,
////       )),
////     ]),
////     required: Some(["location"]),
////   ),
//// )
//// ```

import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// ToolName - Validated tool name (opaque type)
// =============================================================================

/// Error when creating a ToolName
pub type ToolNameError {
  /// Tool name is empty
  EmptyToolName
  /// Tool name contains invalid characters (must match ^[a-zA-Z0-9_-]+$)
  InvalidToolNameCharacters(name: String)
  /// Tool name exceeds maximum length of 64 characters
  ToolNameTooLong(name: String, length: Int)
}

/// A validated tool name that conforms to Anthropic's requirements.
///
/// Tool names must match the regex pattern `^[a-zA-Z0-9_-]{1,64}$`:
/// - Only alphanumeric characters, underscores, and hyphens
/// - Between 1 and 64 characters in length
///
/// Use `tool_name()` to create a validated ToolName, or `tool_name_unchecked()`
/// for cases where you trust the input (e.g., constants or API responses).
pub opaque type ToolName {
  ToolName(name: String)
}

/// Create a validated tool name.
///
/// Returns `Ok(ToolName)` if the name matches Anthropic's requirements:
/// - Non-empty
/// - Only alphanumeric characters, underscores, and hyphens
/// - Maximum 64 characters
///
/// ## Examples
///
/// ```gleam
/// tool_name("get_weather")  // Ok(ToolName)
/// tool_name("my-tool-123")  // Ok(ToolName)
/// tool_name("")             // Error(EmptyToolName)
/// tool_name("has spaces")   // Error(InvalidToolNameCharacters(...))
/// ```
pub fn tool_name(raw: String) -> Result(ToolName, ToolNameError) {
  case raw {
    "" -> Error(EmptyToolName)
    _ -> {
      let length = string.length(raw)
      case length > 64 {
        True -> Error(ToolNameTooLong(name: raw, length: length))
        False -> {
          case is_valid_tool_name_string(raw) {
            True -> Ok(ToolName(raw))
            False -> Error(InvalidToolNameCharacters(name: raw))
          }
        }
      }
    }
  }
}

/// Create a ToolName without validation.
///
/// Use this only when you trust the input, such as:
/// - Compile-time constants
/// - Values received from the Anthropic API
/// - Values already validated elsewhere
///
/// For user input or untrusted sources, use `tool_name()` instead.
pub fn tool_name_unchecked(raw: String) -> ToolName {
  ToolName(raw)
}

/// Get the raw string value from a ToolName.
///
/// Use this when you need to serialize the name to JSON or display it.
pub fn tool_name_to_string(name: ToolName) -> String {
  name.name
}

/// Convert a ToolNameError to a human-readable string.
pub fn tool_name_error_to_string(error: ToolNameError) -> String {
  case error {
    EmptyToolName -> "Tool name cannot be empty"
    InvalidToolNameCharacters(name) ->
      "Tool name '"
      <> name
      <> "' contains invalid characters (only a-z, A-Z, 0-9, _, - allowed)"
    ToolNameTooLong(name, length) ->
      "Tool name '"
      <> name
      <> "' is too long ("
      <> string.inspect(length)
      <> " characters, max 64)"
  }
}

/// Check if a string only contains valid tool name characters
fn is_valid_tool_name_string(name: String) -> Bool {
  name
  |> string.to_graphemes
  |> list.all(fn(char) { is_alphanumeric(char) || char == "_" || char == "-" })
}

/// Check if a character is alphanumeric (a-z, A-Z, 0-9)
fn is_alphanumeric(char: String) -> Bool {
  let lower =
    char == "a"
    || char == "b"
    || char == "c"
    || char == "d"
    || char == "e"
    || char == "f"
    || char == "g"
    || char == "h"
    || char == "i"
    || char == "j"
    || char == "k"
    || char == "l"
    || char == "m"
    || char == "n"
    || char == "o"
    || char == "p"
    || char == "q"
    || char == "r"
    || char == "s"
    || char == "t"
    || char == "u"
    || char == "v"
    || char == "w"
    || char == "x"
    || char == "y"
    || char == "z"

  let upper =
    char == "A"
    || char == "B"
    || char == "C"
    || char == "D"
    || char == "E"
    || char == "F"
    || char == "G"
    || char == "H"
    || char == "I"
    || char == "J"
    || char == "K"
    || char == "L"
    || char == "M"
    || char == "N"
    || char == "O"
    || char == "P"
    || char == "Q"
    || char == "R"
    || char == "S"
    || char == "T"
    || char == "U"
    || char == "V"
    || char == "W"
    || char == "X"
    || char == "Y"
    || char == "Z"

  let digit =
    char == "0"
    || char == "1"
    || char == "2"
    || char == "3"
    || char == "4"
    || char == "5"
    || char == "6"
    || char == "7"
    || char == "8"
    || char == "9"

  lower || upper || digit
}

// =============================================================================
// PropertySchema - Schema for individual properties
// =============================================================================

/// Schema for a single property in a tool's input
pub type PropertySchema {
  PropertySchema(
    /// The JSON type of the property (e.g., "string", "number", "boolean", "array", "object")
    property_type: String,
    /// Human-readable description of the property
    description: Option(String),
    /// If this is an enum, the allowed values
    enum_values: Option(List(String)),
    /// For array types, the schema of items
    items: Option(PropertySchema),
    /// For object types, nested properties
    properties: Option(List(#(String, PropertySchema))),
    /// For object types, which nested properties are required
    required: Option(List(String)),
  )
}

/// Create a simple property schema with just a type
pub fn property(property_type: String) -> PropertySchema {
  PropertySchema(
    property_type: property_type,
    description: None,
    enum_values: None,
    items: None,
    properties: None,
    required: None,
  )
}

/// Create a property schema with type and description
pub fn property_with_description(
  property_type: String,
  description: String,
) -> PropertySchema {
  PropertySchema(
    property_type: property_type,
    description: Some(description),
    enum_values: None,
    items: None,
    properties: None,
    required: None,
  )
}

/// Create an enum property schema
pub fn enum_property(
  description: Option(String),
  values: List(String),
) -> PropertySchema {
  PropertySchema(
    property_type: "string",
    description: description,
    enum_values: Some(values),
    items: None,
    properties: None,
    required: None,
  )
}

/// Create an array property schema
pub fn array_property(
  description: Option(String),
  item_schema: PropertySchema,
) -> PropertySchema {
  PropertySchema(
    property_type: "array",
    description: description,
    enum_values: None,
    items: Some(item_schema),
    properties: None,
    required: None,
  )
}

/// Create an object property schema with nested properties
pub fn object_property(
  description: Option(String),
  properties: List(#(String, PropertySchema)),
  required: List(String),
) -> PropertySchema {
  PropertySchema(
    property_type: "object",
    description: description,
    enum_values: None,
    items: None,
    properties: Some(properties),
    required: Some(required),
  )
}

/// Encode a PropertySchema to JSON
pub fn property_schema_to_json(schema: PropertySchema) -> Json {
  let base_fields = [#("type", json.string(schema.property_type))]

  let with_description = case schema.description {
    Some(desc) ->
      list.append(base_fields, [#("description", json.string(desc))])
    None -> base_fields
  }

  let with_enum = case schema.enum_values {
    Some(values) ->
      list.append(with_description, [
        #("enum", json.array(values, json.string)),
      ])
    None -> with_description
  }

  let with_items = case schema.items {
    Some(item_schema) ->
      list.append(with_enum, [#("items", property_schema_to_json(item_schema))])
    None -> with_enum
  }

  let with_properties = case schema.properties {
    Some(props) -> {
      let props_json =
        props
        |> list.map(fn(pair) {
          let #(name, prop_schema) = pair
          #(name, property_schema_to_json(prop_schema))
        })
      list.append(with_items, [#("properties", json.object(props_json))])
    }
    None -> with_items
  }

  let with_required = case schema.required {
    Some(req) ->
      list.append(with_properties, [
        #("required", json.array(req, json.string)),
      ])
    None -> with_properties
  }

  json.object(with_required)
}

// =============================================================================
// InputSchema - Schema for tool input
// =============================================================================

/// Schema defining the input parameters for a tool
pub type InputSchema {
  InputSchema(
    /// Always "object" for Anthropic tools
    schema_type: String,
    /// Property definitions for the input object
    properties: Option(List(#(String, PropertySchema))),
    /// List of required property names
    required: Option(List(String)),
  )
}

/// Create an empty input schema (for tools with no parameters)
pub fn empty_input_schema() -> InputSchema {
  InputSchema(schema_type: "object", properties: None, required: None)
}

/// Create an input schema with properties
pub fn input_schema(
  properties: List(#(String, PropertySchema)),
  required: List(String),
) -> InputSchema {
  InputSchema(
    schema_type: "object",
    properties: Some(properties),
    required: Some(required),
  )
}

/// Encode an InputSchema to JSON
pub fn input_schema_to_json(schema: InputSchema) -> Json {
  let base_fields = [#("type", json.string(schema.schema_type))]

  let with_properties = case schema.properties {
    Some(props) -> {
      let props_json =
        props
        |> list.map(fn(pair) {
          let #(name, prop_schema) = pair
          #(name, property_schema_to_json(prop_schema))
        })
      list.append(base_fields, [#("properties", json.object(props_json))])
    }
    None -> base_fields
  }

  let with_required = case schema.required {
    Some(req) ->
      list.append(with_properties, [
        #("required", json.array(req, json.string)),
      ])
    None -> with_properties
  }

  json.object(with_required)
}

// =============================================================================
// Tool - Complete tool definition
// =============================================================================

/// A tool definition that can be provided to Claude
pub type Tool {
  Tool(
    /// The validated name of the tool
    name: ToolName,
    /// Human-readable description of what the tool does
    description: Option(String),
    /// JSON Schema defining the tool's input parameters
    input_schema: InputSchema,
  )
}

/// Encode a Tool to JSON
pub fn tool_to_json(t: Tool) -> Json {
  let base_fields = [
    #("name", json.string(tool_name_to_string(t.name))),
    #("input_schema", input_schema_to_json(t.input_schema)),
  ]

  let with_description = case t.description {
    Some(desc) ->
      list.append(base_fields, [#("description", json.string(desc))])
    None -> base_fields
  }

  json.object(with_description)
}

/// Convert a tool to a JSON string
pub fn tool_to_json_string(t: Tool) -> String {
  t
  |> tool_to_json
  |> json.to_string
}

/// Encode a list of tools to JSON
pub fn tools_to_json(tools: List(Tool)) -> Json {
  json.array(tools, tool_to_json)
}

// =============================================================================
// ToolChoice - How Claude should choose tools
// =============================================================================

/// Specifies how Claude should choose which tool to use
pub type ToolChoice {
  /// Claude decides whether to use a tool and which one
  Auto
  /// Claude must use one of the provided tools
  Any
  /// Claude must use the specified tool (by name)
  SpecificTool(name: String)
  /// Claude should not use any tools (respond directly)
  NoTool
}

/// Encode a ToolChoice to JSON
pub fn tool_choice_to_json(choice: ToolChoice) -> Json {
  case choice {
    Auto -> json.object([#("type", json.string("auto"))])
    Any -> json.object([#("type", json.string("any"))])
    SpecificTool(name) ->
      json.object([#("type", json.string("tool")), #("name", json.string(name))])
    NoTool -> json.object([#("type", json.string("none"))])
  }
}

// =============================================================================
// Tool Result Utilities
// =============================================================================

/// Represents a tool call extracted from a response
pub type ToolCall {
  ToolCall(
    /// Unique identifier for this tool call
    id: String,
    /// Name of the tool being called
    name: String,
    /// JSON string of input arguments
    input: String,
  )
}

/// Represents the result of executing a tool
pub type ToolResult {
  /// Successful tool execution
  ToolSuccess(
    /// ID of the tool call this responds to
    tool_use_id: String,
    /// The result content
    content: String,
  )
  /// Failed tool execution
  ToolFailure(
    /// ID of the tool call this responds to
    tool_use_id: String,
    /// Error message
    error: String,
  )
}

/// Get the tool_use_id from a ToolResult
pub fn tool_result_id(result: ToolResult) -> String {
  case result {
    ToolSuccess(tool_use_id, _) -> tool_use_id
    ToolFailure(tool_use_id, _) -> tool_use_id
  }
}

/// Check if a tool result is successful
pub fn is_tool_success(result: ToolResult) -> Bool {
  case result {
    ToolSuccess(_, _) -> True
    ToolFailure(_, _) -> False
  }
}

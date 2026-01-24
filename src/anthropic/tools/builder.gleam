//// Fluent builder for tool definitions
////
//// This module provides an ergonomic builder API for creating tool definitions.
//// The builder pattern allows for type-safe, readable tool construction.
////
//// ## Example
////
//// ```gleam
//// let weather_tool =
////   tool_builder("get_weather")
////   |> with_description("Get the current weather for a location")
////   |> add_string_param("location", "City and state, e.g. 'San Francisco, CA'", True)
////   |> add_enum_param("unit", "Temperature unit", ["celsius", "fahrenheit"], False)
////   |> build()
////
//// // For tools with no parameters
//// let time_tool =
////   tool_builder("get_time")
////   |> with_description("Get the current time")
////   |> build_simple()
//// ```

import anthropic/tool.{
  type PropertySchema, type Tool, type ToolName, type ToolNameError, InputSchema,
  PropertySchema, Tool, tool_name, tool_name_error_to_string,
  tool_name_unchecked,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

// =============================================================================
// Builder Types
// =============================================================================

/// Builder state for constructing a Tool
pub type ToolBuilder {
  ToolBuilder(
    /// Name of the tool
    name: String,
    /// Optional description
    description: Option(String),
    /// Properties accumulated so far
    properties: List(#(String, PropertySchema)),
    /// Required property names
    required: List(String),
  )
}

// =============================================================================
// Builder Initialization
// =============================================================================

/// Start building a new tool with the given name
pub fn tool_builder(name: String) -> ToolBuilder {
  ToolBuilder(name: name, description: None, properties: [], required: [])
}

/// Start building a new tool with name and description
pub fn tool_builder_with_description(
  name: String,
  description: String,
) -> ToolBuilder {
  ToolBuilder(
    name: name,
    description: Some(description),
    properties: [],
    required: [],
  )
}

// =============================================================================
// Builder Methods
// =============================================================================

/// Set the description for the tool
pub fn with_description(
  builder: ToolBuilder,
  description: String,
) -> ToolBuilder {
  ToolBuilder(..builder, description: Some(description))
}

/// Add a string parameter
pub fn add_string_param(
  builder: ToolBuilder,
  name: String,
  description: String,
  is_required: Bool,
) -> ToolBuilder {
  let prop =
    PropertySchema(
      property_type: "string",
      description: Some(description),
      enum_values: None,
      items: None,
      properties: None,
      required: None,
    )

  add_property(builder, name, prop, is_required)
}

/// Add a number parameter
pub fn add_number_param(
  builder: ToolBuilder,
  name: String,
  description: String,
  is_required: Bool,
) -> ToolBuilder {
  let prop =
    PropertySchema(
      property_type: "number",
      description: Some(description),
      enum_values: None,
      items: None,
      properties: None,
      required: None,
    )

  add_property(builder, name, prop, is_required)
}

/// Add an integer parameter
pub fn add_integer_param(
  builder: ToolBuilder,
  name: String,
  description: String,
  is_required: Bool,
) -> ToolBuilder {
  let prop =
    PropertySchema(
      property_type: "integer",
      description: Some(description),
      enum_values: None,
      items: None,
      properties: None,
      required: None,
    )

  add_property(builder, name, prop, is_required)
}

/// Add a boolean parameter
pub fn add_boolean_param(
  builder: ToolBuilder,
  name: String,
  description: String,
  is_required: Bool,
) -> ToolBuilder {
  let prop =
    PropertySchema(
      property_type: "boolean",
      description: Some(description),
      enum_values: None,
      items: None,
      properties: None,
      required: None,
    )

  add_property(builder, name, prop, is_required)
}

/// Add an enum parameter (string with allowed values)
pub fn add_enum_param(
  builder: ToolBuilder,
  name: String,
  description: String,
  values: List(String),
  is_required: Bool,
) -> ToolBuilder {
  let prop =
    PropertySchema(
      property_type: "string",
      description: Some(description),
      enum_values: Some(values),
      items: None,
      properties: None,
      required: None,
    )

  add_property(builder, name, prop, is_required)
}

/// Add an array parameter with string items
pub fn add_string_array_param(
  builder: ToolBuilder,
  name: String,
  description: String,
  item_description: String,
  is_required: Bool,
) -> ToolBuilder {
  let item_schema =
    PropertySchema(
      property_type: "string",
      description: Some(item_description),
      enum_values: None,
      items: None,
      properties: None,
      required: None,
    )

  let prop =
    PropertySchema(
      property_type: "array",
      description: Some(description),
      enum_values: None,
      items: Some(item_schema),
      properties: None,
      required: None,
    )

  add_property(builder, name, prop, is_required)
}

/// Add an array parameter with number items
pub fn add_number_array_param(
  builder: ToolBuilder,
  name: String,
  description: String,
  is_required: Bool,
) -> ToolBuilder {
  let item_schema =
    PropertySchema(
      property_type: "number",
      description: None,
      enum_values: None,
      items: None,
      properties: None,
      required: None,
    )

  let prop =
    PropertySchema(
      property_type: "array",
      description: Some(description),
      enum_values: None,
      items: Some(item_schema),
      properties: None,
      required: None,
    )

  add_property(builder, name, prop, is_required)
}

/// Add a custom property schema
pub fn add_property(
  builder: ToolBuilder,
  name: String,
  property: PropertySchema,
  is_required: Bool,
) -> ToolBuilder {
  let new_properties = list.append(builder.properties, [#(name, property)])
  let new_required = case is_required {
    True -> list.append(builder.required, [name])
    False -> builder.required
  }

  ToolBuilder(..builder, properties: new_properties, required: new_required)
}

/// Add an object parameter with nested properties
pub fn add_object_param(
  builder: ToolBuilder,
  name: String,
  description: String,
  nested_properties: List(#(String, PropertySchema)),
  nested_required: List(String),
  is_required: Bool,
) -> ToolBuilder {
  let prop =
    PropertySchema(
      property_type: "object",
      description: Some(description),
      enum_values: None,
      items: None,
      properties: Some(nested_properties),
      required: Some(nested_required),
    )

  add_property(builder, name, prop, is_required)
}

// =============================================================================
// Build Methods
// =============================================================================

/// Build the tool from the builder state without validation.
///
/// Use this when you trust the tool name is valid (e.g., hardcoded constants).
/// For untrusted input, use `build_validated()` instead.
pub fn build(builder: ToolBuilder) -> Tool {
  let input_schema = case builder.properties {
    [] -> InputSchema(schema_type: "object", properties: None, required: None)
    props ->
      InputSchema(
        schema_type: "object",
        properties: Some(props),
        required: case builder.required {
          [] -> None
          reqs -> Some(reqs)
        },
      )
  }

  Tool(
    name: tool_name_unchecked(builder.name),
    description: builder.description,
    input_schema: input_schema,
  )
}

/// Build a simple tool with no parameters without validation.
///
/// Use this when you trust the tool name is valid (e.g., hardcoded constants).
/// For untrusted input, use `build_validated()` instead.
pub fn build_simple(builder: ToolBuilder) -> Tool {
  Tool(
    name: tool_name_unchecked(builder.name),
    description: builder.description,
    input_schema: InputSchema(
      schema_type: "object",
      properties: None,
      required: None,
    ),
  )
}

// =============================================================================
// Validation
// =============================================================================

/// Validation error for tool definitions
pub type ToolBuilderError {
  /// Tool name validation failed
  InvalidToolName(error: ToolNameError)
  /// Duplicate property name
  DuplicateProperty(name: String)
}

/// Convert a ToolBuilderError to a human-readable string
pub fn builder_error_to_string(error: ToolBuilderError) -> String {
  case error {
    InvalidToolName(name_error) -> tool_name_error_to_string(name_error)
    DuplicateProperty(name) -> "Duplicate property name: " <> name
  }
}

/// Validate a tool name according to Anthropic's requirements.
///
/// Must match regex: ^[a-zA-Z0-9_-]{1,64}$
///
/// Returns the validated ToolName on success.
pub fn validate_name(name: String) -> Result(ToolName, ToolBuilderError) {
  tool_name(name)
  |> result.map_error(InvalidToolName)
}

/// Build and validate the tool.
///
/// This validates that:
/// - The tool name matches Anthropic's requirements (alphanumeric, _, -, 1-64 chars)
/// - No duplicate property names exist
///
/// Use this for user-provided or untrusted tool names.
pub fn build_validated(builder: ToolBuilder) -> Result(Tool, ToolBuilderError) {
  case validate_name(builder.name) {
    Error(err) -> Error(err)
    Ok(validated_name) -> {
      // Check for duplicate properties
      let prop_names = list.map(builder.properties, fn(p) { p.0 })
      case has_duplicates(prop_names) {
        True -> {
          let dup = find_first_duplicate(prop_names)
          Error(DuplicateProperty(name: option.unwrap(dup, "")))
        }
        False -> {
          let input_schema = case builder.properties {
            [] ->
              InputSchema(
                schema_type: "object",
                properties: None,
                required: None,
              )
            props ->
              InputSchema(
                schema_type: "object",
                properties: Some(props),
                required: case builder.required {
                  [] -> None
                  reqs -> Some(reqs)
                },
              )
          }
          Ok(Tool(
            name: validated_name,
            description: builder.description,
            input_schema: input_schema,
          ))
        }
      }
    }
  }
}

// =============================================================================
// Helper Functions
// =============================================================================

fn has_duplicates(items: List(String)) -> Bool {
  list.length(items) != list.length(list.unique(items))
}

fn find_first_duplicate(items: List(String)) -> Option(String) {
  find_first_duplicate_helper(items, [])
}

fn find_first_duplicate_helper(
  remaining: List(String),
  seen: List(String),
) -> Option(String) {
  case remaining {
    [] -> None
    [first, ..rest] -> {
      case list.contains(seen, first) {
        True -> Some(first)
        False -> find_first_duplicate_helper(rest, [first, ..seen])
      }
    }
  }
}

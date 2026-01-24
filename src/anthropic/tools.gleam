//// Tool use utilities for handling the complete tool workflow
////
//// This module provides utilities for:
//// - Extracting tool calls from responses
//// - Building tool result messages
//// - Managing the tool_use -> execute -> tool_result flow
////
//// ## Tool Use Workflow
////
//// 1. Send a request with tools defined
//// 2. Claude responds with tool_use blocks (stop_reason: "tool_use")
//// 3. Extract tool calls from the response
//// 4. Execute the tools and collect results
//// 5. Send a new request with tool_result blocks
//// 6. Claude responds with the final answer
////
//// ## Example
////
//// ```gleam
//// // Step 1: Create request with tools
//// let request = create_request(model, messages, max_tokens)
////   |> with_tools([weather_tool])
////
//// // Step 2: Get response
//// let response = api.create_message(client, request)
////
//// // Step 3: Check for tool use and extract calls
//// case needs_tool_execution(response) {
////   True -> {
////     let tool_calls = extract_tool_calls(response)
////     // Step 4: Execute tools and build results
////     let results = list.map(tool_calls, fn(call) {
////       let result = execute_my_tool(call.name, call.input)
////       tool_success(call.id, result)
////     })
////     // Step 5: Continue conversation with tool results
////     let messages = build_tool_result_messages(response, results)
////     let next_request = create_request(model, messages, max_tokens)
////     api.create_message(client, next_request)
////   }
////   False -> response
//// }
//// ```

import anthropic/types/message.{
  type ContentBlock, type Message, Assistant, Message, ToolResultBlock,
  ToolUseBlock, User,
}
import anthropic/types/request.{type CreateMessageResponse, ToolUse}
import anthropic/types/tool.{
  type ToolCall, type ToolResult, ToolCall, ToolFailure, ToolSuccess,
}
import gleam/list
import gleam/option.{type Option, None, Some}

// =============================================================================
// Tool Call Extraction (Issue #15)
// =============================================================================

/// Check if a response requires tool execution
/// Returns True if stop_reason is ToolUse
pub fn needs_tool_execution(response: CreateMessageResponse) -> Bool {
  case response.stop_reason {
    Some(ToolUse) -> True
    _ -> False
  }
}

/// Extract all tool calls from a response
pub fn extract_tool_calls(response: CreateMessageResponse) -> List(ToolCall) {
  response.content
  |> list.filter_map(fn(block) {
    case block {
      ToolUseBlock(id: id, name: name, input: input) ->
        Ok(ToolCall(id: id, name: name, input: input))
      _ -> Error(Nil)
    }
  })
}

/// Extract a specific tool call by ID
pub fn get_tool_call_by_id(
  response: CreateMessageResponse,
  tool_id: String,
) -> Result(ToolCall, Nil) {
  extract_tool_calls(response)
  |> list.find(fn(call) { call.id == tool_id })
}

/// Extract tool calls by name
pub fn get_tool_calls_by_name(
  response: CreateMessageResponse,
  tool_name: String,
) -> List(ToolCall) {
  extract_tool_calls(response)
  |> list.filter(fn(call) { call.name == tool_name })
}

/// Get the first tool call from a response
pub fn get_first_tool_call(
  response: CreateMessageResponse,
) -> Result(ToolCall, Nil) {
  extract_tool_calls(response)
  |> list.first
}

/// Count the number of tool calls in a response
pub fn count_tool_calls(response: CreateMessageResponse) -> Int {
  extract_tool_calls(response)
  |> list.length
}

/// Get all unique tool names from a response
pub fn get_tool_names(response: CreateMessageResponse) -> List(String) {
  extract_tool_calls(response)
  |> list.map(fn(call) { call.name })
  |> list.unique
}

/// Check if a response contains a specific tool call
pub fn has_tool_call(response: CreateMessageResponse, tool_name: String) -> Bool {
  extract_tool_calls(response)
  |> list.any(fn(call) { call.name == tool_name })
}

// =============================================================================
// Tool Result Building (Issue #16)
// =============================================================================

/// Create a tool result content block from a ToolResult
pub fn tool_result_to_content_block(result: ToolResult) -> ContentBlock {
  case result {
    ToolSuccess(tool_use_id, content) ->
      ToolResultBlock(
        tool_use_id: tool_use_id,
        content: content,
        is_error: False,
      )
    ToolFailure(tool_use_id, error) ->
      ToolResultBlock(tool_use_id: tool_use_id, content: error, is_error: True)
  }
}

/// Create a user message with tool results
pub fn create_tool_result_message(results: List(ToolResult)) -> Message {
  let content = list.map(results, tool_result_to_content_block)
  Message(role: User, content: content)
}

/// Build the complete message list for continuing a conversation after tool use
/// This includes the original messages, the assistant's tool use response,
/// and the user's tool results
pub fn build_tool_result_messages(
  original_messages: List(Message),
  assistant_response: CreateMessageResponse,
  tool_results: List(ToolResult),
) -> List(Message) {
  // Add the assistant's response (with tool_use blocks)
  let assistant_message =
    Message(role: Assistant, content: assistant_response.content)

  // Add the user's tool results
  let tool_result_message = create_tool_result_message(tool_results)

  list.append(original_messages, [assistant_message, tool_result_message])
}

/// Simplified version: build messages from just the response and results
/// Assumes original messages are tracked elsewhere
pub fn build_continuation_messages(
  assistant_response: CreateMessageResponse,
  tool_results: List(ToolResult),
) -> List(Message) {
  let assistant_message =
    Message(role: Assistant, content: assistant_response.content)
  let tool_result_message = create_tool_result_message(tool_results)
  [assistant_message, tool_result_message]
}

// =============================================================================
// Convenience Functions
// =============================================================================

/// Create a successful tool result for a specific tool call
pub fn success_for_call(call: ToolCall, content: String) -> ToolResult {
  ToolSuccess(tool_use_id: call.id, content: content)
}

/// Create a failed tool result for a specific tool call
pub fn failure_for_call(call: ToolCall, error: String) -> ToolResult {
  ToolFailure(tool_use_id: call.id, error: error)
}

/// Execute a handler function on each tool call and collect results
/// The handler should return Ok(content) for success or Error(message) for failure
pub fn execute_tool_calls(
  calls: List(ToolCall),
  handler: fn(ToolCall) -> Result(String, String),
) -> List(ToolResult) {
  list.map(calls, fn(call) {
    case handler(call) {
      Ok(content) -> ToolSuccess(tool_use_id: call.id, content: content)
      Error(err) -> ToolFailure(tool_use_id: call.id, error: err)
    }
  })
}

/// Execute a handler that returns a ToolResult directly
pub fn map_tool_calls(
  calls: List(ToolCall),
  handler: fn(ToolCall) -> ToolResult,
) -> List(ToolResult) {
  list.map(calls, handler)
}

/// Match a tool call by name and execute the appropriate handler
/// Returns an error message if no handler matches
pub fn dispatch_tool_call(
  call: ToolCall,
  handlers: List(#(String, fn(String) -> Result(String, String))),
) -> ToolResult {
  case list.find(handlers, fn(h) { h.0 == call.name }) {
    Ok(#(_name, handler)) -> {
      case handler(call.input) {
        Ok(content) -> ToolSuccess(tool_use_id: call.id, content: content)
        Error(err) -> ToolFailure(tool_use_id: call.id, error: err)
      }
    }
    Error(_) ->
      ToolFailure(tool_use_id: call.id, error: "Unknown tool: " <> call.name)
  }
}

/// Dispatch multiple tool calls using a handler map
pub fn dispatch_tool_calls(
  calls: List(ToolCall),
  handlers: List(#(String, fn(String) -> Result(String, String))),
) -> List(ToolResult) {
  list.map(calls, fn(call) { dispatch_tool_call(call, handlers) })
}

// =============================================================================
// Validation Utilities
// =============================================================================

/// Check if all tool results are successful
pub fn all_tools_succeeded(results: List(ToolResult)) -> Bool {
  list.all(results, fn(r) {
    case r {
      ToolSuccess(_, _) -> True
      ToolFailure(_, _) -> False
    }
  })
}

/// Check if any tool results failed
pub fn any_tools_failed(results: List(ToolResult)) -> Bool {
  list.any(results, fn(r) {
    case r {
      ToolSuccess(_, _) -> False
      ToolFailure(_, _) -> True
    }
  })
}

/// Get all failed tool results
pub fn get_failures(results: List(ToolResult)) -> List(ToolResult) {
  list.filter(results, fn(r) {
    case r {
      ToolSuccess(_, _) -> False
      ToolFailure(_, _) -> True
    }
  })
}

/// Get all successful tool results
pub fn get_successes(results: List(ToolResult)) -> List(ToolResult) {
  list.filter(results, fn(r) {
    case r {
      ToolSuccess(_, _) -> True
      ToolFailure(_, _) -> False
    }
  })
}

/// Get the error message from a ToolResult if it's a failure
pub fn get_error_message(result: ToolResult) -> Option(String) {
  case result {
    ToolSuccess(_, _) -> None
    ToolFailure(_, error) -> Some(error)
  }
}

/// Get the content from a ToolResult if it's a success
pub fn get_success_content(result: ToolResult) -> Option(String) {
  case result {
    ToolSuccess(_, content) -> Some(content)
    ToolFailure(_, _) -> None
  }
}

# anthropic_gleam

[![Package Version](https://img.shields.io/hexpm/v/anthropic_gleam)](https://hex.pm/packages/anthropic_gleam)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/anthropic_gleam/)

A well-typed, idiomatic Gleam client for Anthropic's Claude API with streaming support and tool use.

## Features

- **Full Messages API Support**: Create conversations with Claude using the Messages API
- **Streaming**: Real-time streaming responses with typed events
- **Tool Use**: Define tools and handle tool calls/results
- **Sans-IO Architecture**: Use any HTTP client with the provided request/response builders
- **Retry Logic**: Automatic retries with exponential backoff for transient failures
- **Request Validation**: Comprehensive request validation before sending
- **Observability Hooks**: Optional logging and telemetry hooks
- **Type Safety**: Strongly typed requests, responses, and errors

## Installation

```sh
gleam add anthropic_gleam@1
```

## Quick Start

```gleam
import anthropic/api
import anthropic/client
import anthropic/config
import anthropic/error
import anthropic/message
import anthropic/request
import gleam/io

pub fn main() {
  // Load configuration (reads ANTHROPIC_API_KEY from environment)
  let assert Ok(cfg) = config.config_options() |> config.load_config()

  // Create client
  let api_client = client.new(cfg)

  // Create a request
  let req = request.new(
    "claude-sonnet-4-20250514",
    [message.user_message("Hello, Claude!")],
    1024,
  )

  // Send the request
  case api.chat(api_client, req) {
    Ok(response) -> io.println(request.response_text(response))
    Error(err) -> io.println("Error: " <> error.error_to_string(err))
  }
}
```

## API Quick Reference

This section provides a quick reference for common function signatures. For complete documentation, see the [hexdocs](https://hexdocs.pm/anthropic_gleam/).

### Request Creation

```gleam
// Simple request (recommended for most cases)
request.new(model: String, messages: List(Message), max_tokens: Int) -> CreateMessageRequest

// Request with options (for bulk configuration)
request.options() -> RequestOptions
request.new_with(model: String, messages: List(Message), opts: RequestOptions) -> CreateMessageRequest

// Deprecated alias (use request.new instead)
request.create_request(model, messages, max_tokens) -> CreateMessageRequest
```

### Request Options

```gleam
// Create default options (max_tokens: 1024)
options() -> RequestOptions

// Set individual options
opt_max_tokens(opts, max_tokens: Int) -> RequestOptions
opt_system(opts, system: String) -> RequestOptions
opt_temperature(opts, temperature: Float) -> RequestOptions
opt_top_p(opts, top_p: Float) -> RequestOptions
opt_top_k(opts, top_k: Int) -> RequestOptions
opt_stop_sequences(opts, sequences: List(String)) -> RequestOptions
opt_stream(opts, stream: Bool) -> RequestOptions
opt_tools(opts, tools: List(Tool)) -> RequestOptions
opt_tool_choice(opts, choice: ToolChoice) -> RequestOptions
```

### Request Modifiers (Pipeline Style)

```gleam
// Modify request after creation
with_system(req, system: String) -> CreateMessageRequest
with_temperature(req, temperature: Float) -> CreateMessageRequest
with_tools(req, tools: List(Tool)) -> CreateMessageRequest
with_tool_choice(req, choice: ToolChoice) -> CreateMessageRequest
with_stream(req, stream: Bool) -> CreateMessageRequest
```

### API Calls

```gleam
// Synchronous message creation
api.chat(client: Client, request: CreateMessageRequest) -> Result(CreateMessageResponse, AnthropicError)

// Streaming message creation
api.chat_stream(client: Client, request: CreateMessageRequest) -> Result(StreamResult, AnthropicError)

// Deprecated alias (use api.chat instead)
api.create_message(client, request) -> Result(CreateMessageResponse, AnthropicError)
```

### Client Initialization

```gleam
// From config
client.new(config: Config) -> Client

// From environment (reads ANTHROPIC_API_KEY)
client.init() -> Result(Client, AnthropicError)

// From explicit API key
client.init_with_key(api_key: String) -> Result(Client, AnthropicError)
```

### Error Constructors

All error constructors require a message argument:

```gleam
error.authentication_error(message: String) -> AnthropicError
error.invalid_request_error(message: String) -> AnthropicError
error.rate_limit_error(message: String) -> AnthropicError
error.overloaded_error(message: String) -> AnthropicError
error.internal_api_error(message: String) -> AnthropicError
error.config_error(reason: String) -> AnthropicError
error.http_error(reason: String) -> AnthropicError
error.network_error(reason: String) -> AnthropicError
error.timeout_error(timeout_ms: Int) -> AnthropicError
error.json_error(reason: String) -> AnthropicError

// No-argument errors
error.missing_api_key_error() -> AnthropicError
error.invalid_api_key_error() -> AnthropicError
```

### Error Helpers

```gleam
error.error_to_string(error: AnthropicError) -> String
error.is_retryable(error: AnthropicError) -> Bool
error.is_rate_limit_error(error: AnthropicError) -> Bool
error.is_authentication_error(error: AnthropicError) -> Bool
error.is_overloaded_error(error: AnthropicError) -> Bool
error.get_status_code(error: AnthropicError) -> Option(Int)
```

### Response Helpers

```gleam
request.response_text(response: CreateMessageResponse) -> String
request.response_has_tool_use(response: CreateMessageResponse) -> Bool
request.response_get_tool_uses(response: CreateMessageResponse) -> List(ToolUseBlock)
request.needs_tool_execution(response: CreateMessageResponse) -> Bool
request.get_pending_tool_calls(response: CreateMessageResponse) -> List(ToolCall)
```

### Hooks

```gleam
// Pre-built hooks
hooks.default_hooks() -> Hooks           // Empty hooks
hooks.no_hooks() -> Hooks                // Alias for default_hooks
hooks.simple_logging_hooks() -> Hooks    // Logs to stdout

// Metrics hooks (requires callback)
hooks.metrics_hooks(on_metric: fn(String, Int) -> Nil) -> Hooks

// Combine multiple hooks
hooks.combine_hooks(first: Hooks, second: Hooks) -> Hooks
hooks.has_hooks(hooks: Hooks) -> Bool
```

### Testing Utilities

```gleam
// Convenience - returns CreateMessageResponse directly
testing.mock_response(text: String) -> CreateMessageResponse
testing.mock_response_with(text, model, stop_reason, input_tokens, output_tokens) -> CreateMessageResponse

// HTTP mocks - returns Response(String) for HTTP layer testing
testing.mock_text_response(text: String) -> Response(String)
testing.mock_tool_use_response(tool_id, tool_name, tool_input) -> Response(String)
testing.mock_error_response(status_code, error_type, message) -> Response(String)
testing.mock_auth_error() -> Response(String)
testing.mock_rate_limit_error() -> Response(String)
testing.mock_overloaded_error() -> Response(String)

// Fixtures - returns pre-built CreateMessageResponse
testing.fixture_simple_response() -> CreateMessageResponse
testing.fixture_tool_use_response() -> CreateMessageResponse
testing.fixture_max_tokens_response() -> CreateMessageResponse
testing.fixture_stop_sequence_response() -> CreateMessageResponse
```

## Configuration

### Environment Variables

Set your API key as an environment variable:

```sh
export ANTHROPIC_API_KEY=sk-ant-...
```

### Programmatic Configuration

```gleam
import anthropic/config

let cfg_result = config.config_options()
  |> config.with_api_key("sk-ant-...")  // Override environment variable
  |> config.with_base_url("https://custom.api.url")  // Custom endpoint
  |> config.with_timeout_ms(120_000)  // 2 minute timeout
  |> config.with_max_retries(5)  // Retry up to 5 times
  |> config.load_config()
```

## Sans-IO Pattern (Bring Your Own HTTP Client)

This library supports a sans-io architecture, allowing you to use any HTTP client:

```gleam
import anthropic/http
import anthropic/error
import anthropic/message
import anthropic/request
import gleam/io

pub fn main() {
  let api_key = "sk-ant-..."
  let base_url = http.default_base_url

  // Build the request
  let req = request.new(
    "claude-sonnet-4-20250514",
    [message.user_message("Hello!")],
    1024,
  )
  let http_request = http.build_messages_request(api_key, base_url, req)

  // Send with YOUR HTTP client (hackney, httpc, fetch on JS, etc.)
  // let http_response = my_http_client.send(http_request)

  // Parse the response
  // case http.parse_messages_response(http_response) {
  //   Ok(response) -> io.println(request.response_text(response))
  //   Error(err) -> io.println(error.error_to_string(err))
  // }
}
```

## Streaming

### Real-Time Streaming (Sans-IO)

For true real-time streaming where you process events as they arrive:

```gleam
import anthropic/http
import anthropic/streaming/handler.{
  finalize_stream, get_event_text, new_streaming_state, process_chunk,
}
import anthropic/message
import anthropic/request
import gleam/io
import gleam/list

pub fn stream_example() {
  let api_key = "sk-ant-..."
  let base_url = http.default_base_url

  // Build streaming request
  let req = request.new(
    "claude-sonnet-4-20250514",
    [message.user_message("Write a short poem")],
    1024,
  )
  let http_request = http.build_streaming_request(api_key, base_url, req)

  // Initialize streaming state
  let state = new_streaming_state()

  // As each chunk arrives from your streaming HTTP client:
  // let #(events, new_state) = process_chunk(state, chunk)

  // Handle events in real-time
  // list.each(events, fn(event) {
  //   case get_event_text(event) {
  //     Ok(text) -> io.print(text)  // Print immediately!
  //     Error(_) -> Nil
  //   }
  // })

  // When stream ends, finalize to get any remaining events
  // let final_events = finalize_stream(final_state)
}
```

### Batch Streaming (Convenience)

For simpler use cases where you don't need real-time processing:

```gleam
import anthropic/api
import anthropic/client
import anthropic/config
import anthropic/message
import anthropic/request
import gleam/io

pub fn batch_stream_example() {
  let assert Ok(cfg) = config.config_options() |> config.load_config()
  let api_client = client.new(cfg)

  let req = request.new(
    "claude-sonnet-4-20250514",
    [message.user_message("Tell me a joke")],
    1024,
  )

  // Stream with api.chat_stream
  case api.chat_stream(api_client, req) {
    Ok(result) -> io.println(api.stream_text(result))
    Error(err) -> io.println("Stream error")
  }
}
```

## Tool Use

### Defining Tools

```gleam
import anthropic/tools/builder.{
  add_enum_param, add_string_param, build, tool_builder, with_description,
}

let weather_tool = tool_builder("get_weather")
  |> with_description("Get the current weather for a location")
  |> add_string_param("location", "City and state, e.g. 'San Francisco, CA'", True)
  |> add_enum_param("unit", "Temperature unit", ["celsius", "fahrenheit"], False)
  |> build()
```

### Using Tools in Requests

```gleam
import anthropic/request.{with_tool_choice, with_tools}
import anthropic/tool.{Auto}

let req = request.new(model, messages, max_tokens)
  |> with_tools([weather_tool])
  |> with_tool_choice(Auto)
```

### Handling Tool Calls

```gleam
import anthropic/api
import anthropic/tools.{
  build_tool_result_messages, dispatch_tool_calls, extract_tool_calls,
  needs_tool_execution,
}
import anthropic/tool.{ToolSuccess}

case api.chat(api_client, req) {
  Ok(response) -> {
    case needs_tool_execution(response) {
      True -> {
        let calls = extract_tool_calls(response)

        // Execute tools using dispatch
        let handlers = [
          #("get_weather", fn(tool_use_id, _input) {
            ToolSuccess(tool_use_id: tool_use_id, content: "{\"temp\": 72, \"condition\": \"sunny\"}")
          }),
        ]
        let results = dispatch_tool_calls(calls, handlers)

        // Continue conversation with results
        let messages = build_tool_result_messages(original_messages, response, results)
        api.chat(api_client, request.new(model, messages, max_tokens))
      }
      False -> Ok(response)
    }
  }
  Error(err) -> Error(err)
}
```

## Error Handling

```gleam
import anthropic/api
import anthropic/error.{
  error_to_string, is_authentication_error, is_rate_limit_error, is_retryable,
}
import gleam/io

case api.chat(api_client, request) {
  Ok(response) -> handle_success(response)
  Error(err) -> {
    io.println("Error: " <> error_to_string(err))

    case is_rate_limit_error(err) {
      True -> io.println("Rate limited - try again later")
      False -> Nil
    }

    case is_authentication_error(err) {
      True -> io.println("Check your API key")
      False -> Nil
    }

    case is_retryable(err) {
      True -> io.println("This error can be retried")
      False -> io.println("This error is permanent")
    }
  }
}
```

## Retry Logic

The client includes automatic retry logic for transient failures:

```gleam
import anthropic/retry.{
  default_retry_config, with_base_delay_ms, with_max_retries,
}

// Configure retries
let retry_config = default_retry_config()
  |> with_max_retries(5)
  |> with_base_delay_ms(500)
```

### Retryable Errors

The following errors are automatically retried:
- Rate limit errors (429)
- Server overload (529)
- Internal server errors (500+)
- Timeouts
- Network errors

## Request Validation

Validate requests before sending:

```gleam
import anthropic/api
import anthropic/error
import anthropic/internal/validation.{is_valid, validate_request}
import gleam/io
import gleam/list

// Full validation with error details
case validate_request(req) {
  Ok(_) -> api.chat(api_client, req)
  Error(errors) -> {
    io.println("Validation errors:")
    list.each(errors, fn(e) {
      io.println("  - " <> validation.errors_to_string([e]))
    })
    Error(error.invalid_request_error("Validation failed"))
  }
}

// Quick boolean check
case is_valid(req) {
  True -> api.chat(api_client, req)
  False -> Error(error.invalid_request_error("Invalid request"))
}
```

## Observability Hooks

Add logging and telemetry:

```gleam
import anthropic/hooks.{
  default_hooks, simple_logging_hooks, with_on_request_end, with_on_request_start,
}
import gleam/int
import gleam/io

// Simple logging
let hooks = simple_logging_hooks()

// Custom hooks
let custom_hooks = default_hooks()
  |> with_on_request_start(fn(event) {
    io.println("Starting request: " <> event.request_id)
  })
  |> with_on_request_end(fn(event) {
    io.println("Request completed in " <> int.to_string(event.duration_ms) <> "ms")
  })
```

## Module Reference

| Module | Description |
|--------|-------------|
| `anthropic/api` | Core API functions for sending requests |
| `anthropic/client` | HTTP client configuration |
| `anthropic/config` | Configuration management |
| `anthropic/http` | Sans-IO HTTP types and request/response builders |
| `anthropic/message` | Message and content block types |
| `anthropic/request` | Request and response types |
| `anthropic/tool` | Tool definition types |
| `anthropic/error` | Error types and helpers |
| `anthropic/streaming` | Streaming event types |
| `anthropic/tools` | Tool use workflow utilities |
| `anthropic/tools/builder` | Fluent builder for tool definitions |
| `anthropic/streaming/handler` | Streaming handler (batch and real-time) |
| `anthropic/streaming/decoder` | Event decoder (low-level) |
| `anthropic/streaming/accumulator` | Stream state accumulator |
| `anthropic/retry` | Retry logic with exponential backoff |
| `anthropic/internal/validation` | Request validation (internal) |
| `anthropic/internal/sse` | SSE parser (internal) |
| `anthropic/internal/decoder` | JSON response decoder (internal) |
| `anthropic/hooks` | Logging and telemetry hooks |
| `anthropic/testing` | Mock responses for testing |

## Development

```sh
gleam build   # Build the project
gleam test    # Run the tests
gleam docs build  # Generate documentation
```

## License

MIT License - see LICENSE file for details.

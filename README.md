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
import anthropic/types/error
import anthropic/types/message
import anthropic/types/request
import gleam/io

pub fn main() {
  // Load configuration (reads ANTHROPIC_API_KEY from environment)
  let assert Ok(cfg) = config.config_options() |> config.load_config()

  // Create client
  let api_client = client.new(cfg)

  // Create a request
  let req = request.create_request(
    "claude-sonnet-4-20250514",
    [message.user_message("Hello, Claude!")],
    1024,
  )

  // Send the request
  case api.create_message(api_client, req) {
    Ok(response) -> io.println(request.response_text(response))
    Error(err) -> io.println("Error: " <> error.error_to_string(err))
  }
}
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
import anthropic/types/error
import anthropic/types/message
import anthropic/types/request
import gleam/io

pub fn main() {
  let api_key = "sk-ant-..."
  let base_url = http.default_base_url

  // Build the request
  let req = request.create_request(
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
import anthropic/types/message
import anthropic/types/request
import gleam/io
import gleam/list

pub fn stream_example() {
  let api_key = "sk-ant-..."
  let base_url = http.default_base_url

  // Build streaming request
  let req = request.create_request(
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
import anthropic/client
import anthropic/config
import anthropic/streaming/handler
import anthropic/types/message
import anthropic/types/request
import gleam/io

pub fn batch_stream_example() {
  let assert Ok(cfg) = config.config_options() |> config.load_config()
  let api_client = client.new(cfg)

  let req = request.create_request(
    "claude-sonnet-4-20250514",
    [message.user_message("Tell me a joke")],
    1024,
  )

  // Batch mode collects all events before returning
  case handler.stream_message(api_client, req) {
    Ok(result) -> io.println(handler.get_full_text(result.events))
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
import anthropic/types/request.{with_tool_choice, with_tools}
import anthropic/types/tool.{Auto}

let req = request.create_request(model, messages, max_tokens)
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
import anthropic/types/tool.{ToolSuccess}

case api.create_message(api_client, req) {
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
        api.create_message(api_client, request.create_request(model, messages, max_tokens))
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
import anthropic/types/error.{
  error_to_string, is_authentication_error, is_rate_limit_error, is_retryable,
}
import gleam/io

case api.create_message(api_client, request) {
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
import anthropic/types/error
import anthropic/validation.{is_valid, validate_request}
import gleam/io
import gleam/list

// Full validation with error details
case validate_request(req) {
  Ok(_) -> api.create_message(api_client, req)
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
  True -> api.create_message(api_client, req)
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
| `anthropic/types/message` | Message and content block types |
| `anthropic/types/request` | Request and response types |
| `anthropic/types/tool` | Tool definition types |
| `anthropic/types/error` | Error types and helpers |
| `anthropic/types/streaming` | Streaming event types |
| `anthropic/tools` | Tool use workflow utilities |
| `anthropic/tools/builder` | Fluent builder for tool definitions |
| `anthropic/streaming/handler` | Streaming handler (batch and real-time) |
| `anthropic/streaming/sse` | SSE parser (low-level) |
| `anthropic/streaming/decoder` | Event decoder (low-level) |
| `anthropic/streaming/accumulator` | Stream state accumulator |
| `anthropic/retry` | Retry logic with exponential backoff |
| `anthropic/validation` | Request validation |
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

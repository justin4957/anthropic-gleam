# anthropic_gleam

[![Package Version](https://img.shields.io/hexpm/v/anthropic_gleam)](https://hex.pm/packages/anthropic_gleam)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/anthropic_gleam/)

A well-typed, idiomatic Gleam client for Anthropic's Claude API with streaming support and tool use.

## Features

- **Full Messages API Support**: Create conversations with Claude using the Messages API
- **Streaming**: Real-time streaming responses with typed events
- **Tool Use**: Define tools and handle tool calls/results
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
    "claude-3-5-haiku-20241022",
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

## Streaming

```gleam
import anthropic/streaming/stream
import anthropic/streaming/events
import gleam/io

// Create a streaming request
let req = request.create_request(model, messages, max_tokens)
  |> request.with_stream(True)

// Handle streaming response
case stream.create_message_stream(client, req) {
  Ok(stream_state) -> {
    // Process events
    let final_state = stream.process_stream(stream_state, fn(event, state) {
      case event {
        events.ContentBlockDelta(_, events.TextDelta(text)) -> {
          io.print(text)
          state
        }
        _ -> state
      }
    })
  }
  Error(err) -> io.println("Stream error: " <> error.error_to_string(err))
}
```

## Tool Use

### Defining Tools

```gleam
import anthropic/tools/builder.{
  tool_builder, with_description, add_string_param, add_enum_param, build
}

let weather_tool = tool_builder("get_weather")
  |> with_description("Get the current weather for a location")
  |> add_string_param("location", "City and state, e.g. 'San Francisco, CA'", True)
  |> add_enum_param("unit", "Temperature unit", ["celsius", "fahrenheit"], False)
  |> build()
```

### Using Tools in Requests

```gleam
import anthropic/types/tool.{Auto}

let req = request.create_request(model, messages, max_tokens)
  |> request.with_tools([weather_tool])
  |> request.with_tool_choice(Auto)
```

### Handling Tool Calls

```gleam
import anthropic/tools.{
  needs_tool_execution, extract_tool_calls, build_tool_result_messages,
  dispatch_tool_calls
}
import anthropic/types/tool.{tool_success}

case api.create_message(client, req) {
  Ok(response) -> {
    case needs_tool_execution(response) {
      True -> {
        let calls = extract_tool_calls(response)

        // Execute tools using dispatch
        let handlers = [
          #("get_weather", fn(input) {
            Ok("{\"temp\": 72, \"condition\": \"sunny\"}")
          }),
        ]
        let results = dispatch_tool_calls(calls, handlers)

        // Continue conversation with results
        let messages = build_tool_result_messages(original_messages, response, results)
        api.create_message(client, request.create_request(model, messages, max_tokens))
      }
      False -> Ok(response)
    }
  }
  Error(err) -> Error(err)
}
```

## Retry Logic

The client includes automatic retry logic for transient failures:

```gleam
import anthropic/retry.{
  default_retry_config, with_max_retries, with_base_delay_ms, retry
}

// Configure retries
let retry_config = default_retry_config()
  |> with_max_retries(5)
  |> with_base_delay_ms(500)

// Execute with retry
let result = retry(retry_config, fn() {
  api.create_message(client, request)
})
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
import anthropic/validation.{validate_request, is_valid}

// Full validation with error details
case validate_request(request) {
  Ok(_) -> api.create_message(client, request)
  Error(errors) -> {
    io.println("Validation errors:")
    list.each(errors, fn(e) {
      io.println("  - " <> validation.error_to_string(e))
    })
    Error(error.invalid_request_error("Validation failed"))
  }
}

// Quick boolean check
case is_valid(request) {
  True -> api.create_message(client, request)
  False -> Error(error.invalid_request_error("Invalid request"))
}
```

## Observability Hooks

Add logging and telemetry:

```gleam
import anthropic/hooks.{
  default_hooks, with_on_request_start, with_on_request_end, simple_logging_hooks
}

// Simple logging
let hooks = simple_logging_hooks()

// Custom hooks
let hooks = default_hooks()
  |> with_on_request_start(fn(event) {
    io.println("Starting request: " <> event.request_id)
  })
  |> with_on_request_end(fn(event) {
    io.println("Request completed in " <> int.to_string(event.duration_ms) <> "ms")
  })
```

## Error Handling

```gleam
import anthropic/types/error.{
  is_retryable, is_rate_limit_error, is_authentication_error, error_to_string
}

case api.create_message(client, request) {
  Ok(response) -> handle_success(response)
  Error(err) -> {
    io.println("Error: " <> error_to_string(err))

    case is_rate_limit_error(err) {
      True -> io.println("Rate limited - try again later")
      False -> Nil
    }

    case is_retryable(err) {
      True -> io.println("This error can be retried")
      False -> io.println("This error is permanent")
    }
  }
}
```

## API Reference

### Modules

| Module | Description |
|--------|-------------|
| `anthropic/api` | Core API functions for sending requests |
| `anthropic/client` | HTTP client configuration |
| `anthropic/config` | Configuration management |
| `anthropic/types/message` | Message and content block types |
| `anthropic/types/request` | Request and response types |
| `anthropic/types/tool` | Tool definition types |
| `anthropic/types/error` | Error types and helpers |
| `anthropic/tools` | Tool use workflow utilities |
| `anthropic/tools/builder` | Fluent builder for tool definitions |
| `anthropic/streaming/stream` | Streaming request handling |
| `anthropic/streaming/events` | Streaming event types |
| `anthropic/retry` | Retry logic with exponential backoff |
| `anthropic/validation` | Request validation |
| `anthropic/hooks` | Logging and telemetry hooks |

## Development

```sh
gleam build   # Build the project
gleam test    # Run the tests
gleam docs build  # Generate documentation
```

## License

MIT License - see LICENSE file for details.

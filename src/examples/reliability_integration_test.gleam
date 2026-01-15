//// Integration test for Reliability Features (A4.1-A4.3)
////
//// Tests retry logic, request validation, and logging hooks with actual API
//// Run with: gleam run -m examples/reliability_integration_test

import anthropic/api
import anthropic/client
import anthropic/config
import anthropic/hooks.{
  type RequestEndEvent, type RequestStartEvent, RequestEndEvent,
  RequestStartEvent, default_hooks, summarize_request, with_on_request_end,
  with_on_request_start,
}
import anthropic/retry.{default_retry_config, with_max_retries}
import anthropic/types/error
import anthropic/types/message
import anthropic/types/request
import anthropic/validation.{
  is_valid, validate_or_error, validate_request, validate_temperature,
}
import gleam/erlang/charlist
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// Main entry point
pub fn main() {
  io.println("===========================================")
  io.println("Reliability Features Integration Test")
  io.println("(A4.1 Retry, A4.2 Validation, A4.3 Hooks)")
  io.println("===========================================")
  io.println("")

  // Get API key
  case get_api_key() {
    Error(Nil) -> {
      io.println("ERROR: ANTHROPIC_API_KEY environment variable not set")
      io.println("Please set it and try again:")
      io.println("  export ANTHROPIC_API_KEY=your-api-key")
    }
    Ok(api_key) -> {
      io.println(
        "API Key: [REDACTED - " <> string.slice(api_key, 0, 8) <> "...]",
      )
      io.println("")
      run_tests(api_key)
    }
  }
}

fn run_tests(api_key: String) {
  // Test 1: Request Validation - Valid Request
  io.println("-------------------------------------------")
  io.println("TEST 1: Request Validation - Valid Request")
  io.println("-------------------------------------------")
  test_validation_valid(api_key)

  io.println("")

  // Test 2: Request Validation - Invalid Requests
  io.println("-------------------------------------------")
  io.println("TEST 2: Request Validation - Invalid Requests")
  io.println("-------------------------------------------")
  test_validation_invalid()

  io.println("")

  // Test 3: Logging Hooks
  io.println("-------------------------------------------")
  io.println("TEST 3: Logging Hooks with API Call")
  io.println("-------------------------------------------")
  test_hooks_with_api(api_key)

  io.println("")

  // Test 4: Retry Logic (simulated - actual retries require triggering rate limits)
  io.println("-------------------------------------------")
  io.println("TEST 4: Retry Logic Configuration")
  io.println("-------------------------------------------")
  test_retry_config()

  io.println("")

  // Test 5: Full Integration - Validation + Hooks + API Call
  io.println("-------------------------------------------")
  io.println("TEST 5: Full Integration Test")
  io.println("-------------------------------------------")
  test_full_integration(api_key)

  io.println("")
  io.println("===========================================")
  io.println("All tests completed!")
  io.println("===========================================")
}

/// Test 1: Validate a properly formed request
fn test_validation_valid(api_key: String) {
  io.println("Creating a valid request...")

  let messages = [message.user_message("What is 2 + 2? Answer briefly.")]

  let req =
    request.create_request("claude-3-5-haiku-20241022", messages, 100)
    |> request.with_temperature(0.7)

  io.println("Request details:")
  io.println("  Model: claude-3-5-haiku-20241022")
  io.println("  Messages: 1 user message")
  io.println("  Max tokens: 100")
  io.println("  Temperature: 0.7")
  io.println("")

  io.println("Running validation...")
  case validate_request(req) {
    Ok(Nil) -> {
      io.println("✓ PASS: Request validation passed")
      io.println("  is_valid() returns: " <> bool_to_string(is_valid(req)))
    }
    Error(errors) -> {
      io.println("✗ FAIL: Request validation failed")
      list.each(errors, fn(e) {
        io.println("  - " <> validation.error_to_string(e))
      })
    }
  }
}

/// Test 2: Validate invalid requests to ensure validation catches errors
fn test_validation_invalid() {
  io.println("Testing validation error detection...")
  io.println("")

  // Test 2a: Empty messages
  io.println("2a. Empty messages list:")
  let empty_req = request.create_request("claude-3-5-haiku-20241022", [], 100)
  case validate_request(empty_req) {
    Ok(Nil) -> io.println("  ✗ FAIL: Should have caught empty messages")
    Error(errors) -> {
      io.println("  ✓ PASS: Caught validation errors:")
      list.each(errors, fn(e) {
        io.println("    - " <> validation.error_to_string(e))
      })
    }
  }

  io.println("")

  // Test 2b: Empty model name
  io.println("2b. Empty model name:")
  let empty_model_req =
    request.create_request("", [message.user_message("Hello")], 100)
  case validate_request(empty_model_req) {
    Ok(Nil) -> io.println("  ✗ FAIL: Should have caught empty model")
    Error(errors) -> {
      io.println("  ✓ PASS: Caught validation errors:")
      list.each(errors, fn(e) {
        io.println("    - " <> validation.error_to_string(e))
      })
    }
  }

  io.println("")

  // Test 2c: Invalid temperature
  io.println("2c. Invalid temperature (1.5):")
  case validate_temperature(Some(1.5)) {
    Ok(Nil) -> io.println("  ✗ FAIL: Should have caught invalid temperature")
    Error(errors) -> {
      io.println("  ✓ PASS: Caught validation errors:")
      list.each(errors, fn(e) {
        io.println("    - " <> validation.error_to_string(e))
      })
    }
  }

  io.println("")

  // Test 2d: Zero max_tokens
  io.println("2d. Zero max_tokens:")
  let zero_tokens_req =
    request.create_request(
      "claude-3-5-haiku-20241022",
      [message.user_message("Hello")],
      0,
    )
  case validate_request(zero_tokens_req) {
    Ok(Nil) -> io.println("  ✗ FAIL: Should have caught zero max_tokens")
    Error(errors) -> {
      io.println("  ✓ PASS: Caught validation errors:")
      list.each(errors, fn(e) {
        io.println("    - " <> validation.error_to_string(e))
      })
    }
  }

  io.println("")

  // Test 2e: validate_or_error integration
  io.println("2e. validate_or_error returns AnthropicError:")
  case validate_or_error(empty_req) {
    Ok(_) -> io.println("  ✗ FAIL: Should have returned error")
    Error(err) -> {
      io.println("  ✓ PASS: Returned AnthropicError:")
      io.println("    " <> error.error_to_string(err))
    }
  }
}

/// Test 3: Test logging hooks with actual API call
fn test_hooks_with_api(api_key: String) {
  io.println("Setting up logging hooks...")

  // Track hook invocations
  let hooks =
    default_hooks()
    |> with_on_request_start(fn(event: RequestStartEvent) {
      io.println("")
      io.println("[HOOK] Request Started:")
      io.println("  Endpoint: " <> event.endpoint)
      io.println("  Request ID: " <> event.request_id)
      io.println("  Model: " <> event.request.model)
      io.println(
        "  Message count: " <> int.to_string(event.request.message_count),
      )
      io.println("  Max tokens: " <> int.to_string(event.request.max_tokens))
      io.println("  Streaming: " <> bool_to_string(event.request.stream))
      Nil
    })
    |> with_on_request_end(fn(event: RequestEndEvent) {
      io.println("")
      io.println("[HOOK] Request Ended:")
      io.println("  Endpoint: " <> event.endpoint)
      io.println("  Request ID: " <> event.request_id)
      io.println("  Duration: " <> int.to_string(event.duration_ms) <> "ms")
      io.println("  Success: " <> bool_to_string(event.success))
      io.println("  Retry count: " <> int.to_string(event.retry_count))
      case event.response {
        Some(resp) -> {
          io.println("  Response ID: " <> resp.id)
          io.println("  Input tokens: " <> int.to_string(resp.input_tokens))
          io.println("  Output tokens: " <> int.to_string(resp.output_tokens))
        }
        None -> Nil
      }
      Nil
    })

  io.println("Hooks configured. Making API request...")
  io.println("")

  // Create config and client
  let assert Ok(cfg) =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  let api_client = client.new(cfg)

  // Create request
  let messages = [
    message.user_message("Say 'Hello from hooks test!' and nothing else."),
  ]
  let req = request.create_request("claude-3-5-haiku-20241022", messages, 50)

  // Emit request start hook manually (since api.create_message doesn't use hooks yet)
  let request_id = hooks.generate_request_id()
  let start_time = get_timestamp_ms()

  hooks.emit_request_start(
    hooks,
    RequestStartEvent(
      endpoint: "/v1/messages",
      request: summarize_request(req),
      timestamp_ms: start_time,
      request_id: request_id,
    ),
  )

  // Make actual API call
  let result = api.create_message(api_client, req)

  let end_time = get_timestamp_ms()
  let duration = end_time - start_time

  // Emit request end hook
  case result {
    Ok(response) -> {
      hooks.emit_request_end(
        hooks,
        RequestEndEvent(
          endpoint: "/v1/messages",
          duration_ms: duration,
          success: True,
          response: Some(hooks.summarize_response(response)),
          error: None,
          request_id: request_id,
          retry_count: 0,
        ),
      )
      io.println("")
      io.println("API Response:")
      io.println("  " <> request.response_text(response))
      io.println("")
      io.println("✓ PASS: Hooks test completed successfully")
    }
    Error(err) -> {
      hooks.emit_request_end(
        hooks,
        RequestEndEvent(
          endpoint: "/v1/messages",
          duration_ms: duration,
          success: False,
          response: None,
          error: Some(err),
          request_id: request_id,
          retry_count: 0,
        ),
      )
      io.println("")
      io.println("✗ FAIL: API call failed: " <> error.error_to_string(err))
    }
  }
}

/// Test 4: Test retry configuration (without triggering actual retries)
fn test_retry_config() {
  io.println("Testing retry configuration...")
  io.println("")

  // Default config
  let default_config = default_retry_config()
  io.println("Default retry config:")
  io.println("  Max retries: " <> int.to_string(default_config.max_retries))
  io.println(
    "  Base delay: " <> int.to_string(default_config.base_delay_ms) <> "ms",
  )
  io.println(
    "  Max delay: " <> int.to_string(default_config.max_delay_ms) <> "ms",
  )
  io.println(
    "  Backoff multiplier: "
    <> float_to_string(default_config.backoff_multiplier),
  )
  io.println(
    "  Jitter factor: " <> float_to_string(default_config.jitter_factor),
  )

  io.println("")

  // Custom config
  let custom_config =
    default_retry_config()
    |> with_max_retries(5)

  io.println("Custom config (5 retries):")
  io.println("  Max retries: " <> int.to_string(custom_config.max_retries))

  io.println("")

  // Calculate expected delays
  io.println("Expected delays (without jitter):")
  io.println(
    "  Attempt 1: "
    <> int.to_string(retry.calculate_delay(default_config, 0))
    <> "ms",
  )
  io.println(
    "  Attempt 2: "
    <> int.to_string(retry.calculate_delay(default_config, 1))
    <> "ms",
  )
  io.println(
    "  Attempt 3: "
    <> int.to_string(retry.calculate_delay(default_config, 2))
    <> "ms",
  )

  io.println("")

  // Test retryable error detection
  io.println("Retryable error detection:")
  let rate_limit_err = error.rate_limit_error("Rate limited")
  let auth_err = error.authentication_error("Invalid key")
  io.println(
    "  Rate limit error retryable: "
    <> bool_to_string(error.is_retryable(rate_limit_err)),
  )
  io.println(
    "  Auth error retryable: " <> bool_to_string(error.is_retryable(auth_err)),
  )

  io.println("")
  io.println("✓ PASS: Retry configuration test completed")
}

/// Test 5: Full integration test with validation + hooks + API
fn test_full_integration(api_key: String) {
  io.println("Running full integration test...")
  io.println("")

  // Step 1: Create and validate request
  io.println("Step 1: Creating request...")
  let messages = [
    message.user_message("What is the capital of France? Answer in one word."),
  ]
  let req =
    request.create_request("claude-3-5-haiku-20241022", messages, 50)
    |> request.with_temperature(0.5)

  io.println("Step 2: Validating request...")
  case validate_or_error(req) {
    Error(err) -> {
      io.println("✗ FAIL: Validation failed: " <> error.error_to_string(err))
    }
    Ok(validated_req) -> {
      io.println("✓ Request validated successfully")
      io.println("")

      // Step 3: Setup hooks for logging
      io.println("Step 3: Setting up hooks...")
      let hooks =
        default_hooks()
        |> with_on_request_start(fn(event: RequestStartEvent) {
          io.println(
            "[LOG] Starting request to "
            <> event.endpoint
            <> " (ID: "
            <> event.request_id
            <> ")",
          )
          Nil
        })
        |> with_on_request_end(fn(event: RequestEndEvent) {
          io.println(
            "[LOG] Request completed in "
            <> int.to_string(event.duration_ms)
            <> "ms, success="
            <> bool_to_string(event.success),
          )
          Nil
        })

      // Step 4: Create client
      io.println("Step 4: Creating API client...")
      let assert Ok(cfg) =
        config.config_options()
        |> config.with_api_key(api_key)
        |> config.load_config()

      let api_client = client.new(cfg)

      // Step 5: Make API call with hooks
      io.println("Step 5: Making API call...")
      io.println("")

      let request_id = hooks.generate_request_id()
      let start_time = get_timestamp_ms()

      hooks.emit_request_start(
        hooks,
        RequestStartEvent(
          endpoint: "/v1/messages",
          request: summarize_request(validated_req),
          timestamp_ms: start_time,
          request_id: request_id,
        ),
      )

      case api.create_message(api_client, validated_req) {
        Ok(response) -> {
          let end_time = get_timestamp_ms()
          hooks.emit_request_end(
            hooks,
            RequestEndEvent(
              endpoint: "/v1/messages",
              duration_ms: end_time - start_time,
              success: True,
              response: Some(hooks.summarize_response(response)),
              error: None,
              request_id: request_id,
              retry_count: 0,
            ),
          )

          io.println("")
          io.println("Step 6: Processing response...")
          io.println("  Response ID: " <> response.id)
          io.println("  Model: " <> response.model)
          io.println(
            "  Input tokens: " <> int.to_string(response.usage.input_tokens),
          )
          io.println(
            "  Output tokens: " <> int.to_string(response.usage.output_tokens),
          )
          io.println("")
          io.println("  Claude says: " <> request.response_text(response))
          io.println("")
          io.println("✓ PASS: Full integration test completed successfully")
        }
        Error(err) -> {
          let end_time = get_timestamp_ms()
          hooks.emit_request_end(
            hooks,
            RequestEndEvent(
              endpoint: "/v1/messages",
              duration_ms: end_time - start_time,
              success: False,
              response: None,
              error: Some(err),
              request_id: request_id,
              retry_count: 0,
            ),
          )
          io.println("")
          io.println("✗ FAIL: API call failed: " <> error.error_to_string(err))
        }
      }
    }
  }
}

// =============================================================================
// Helper Functions
// =============================================================================

fn get_api_key() -> Result(String, Nil) {
  case get_env("ANTHROPIC_API_KEY") {
    Ok(key) ->
      case string.is_empty(string.trim(key)) {
        True -> Error(Nil)
        False -> Ok(key)
      }
    Error(_) -> Error(Nil)
  }
}

@external(erlang, "os", "getenv")
fn os_getenv(name: charlist.Charlist) -> charlist.Charlist

fn get_env(name: String) -> Result(String, Nil) {
  let result = os_getenv(charlist.from_string(name))
  let str = charlist.to_string(result)
  case str {
    "false" -> Error(Nil)
    "" -> Error(Nil)
    value -> Ok(value)
  }
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

fn float_to_string(f: Float) -> String {
  do_float_to_string(f)
}

@external(erlang, "erlang", "float_to_binary")
fn do_float_to_string(f: Float) -> String

@external(erlang, "os", "system_time")
fn system_time_native() -> Int

fn get_timestamp_ms() -> Int {
  system_time_native() / 1000
}

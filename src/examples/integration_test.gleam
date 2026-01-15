//// Integration test for Anthropic API
////
//// This script tests actual communication with the Claude API
//// Run with: gleam run -m examples/integration_test

import anthropic/api
import anthropic/client
import anthropic/config
import anthropic/types/error
import anthropic/types/message
import anthropic/types/request
import gleam/erlang/charlist
import gleam/io
import gleam/option.{None, Some}
import gleam/string

/// Main entry point
pub fn main() {
  io.println("===========================================")
  io.println("Anthropic API Integration Test")
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
  // Test 1: Simple text message
  io.println("-------------------------------------------")
  io.println("TEST 1: Simple Text Message")
  io.println("-------------------------------------------")
  test_simple_message(api_key)

  io.println("")

  // Test 2: Multi-turn conversation
  io.println("-------------------------------------------")
  io.println("TEST 2: Multi-turn Conversation")
  io.println("-------------------------------------------")
  test_conversation(api_key)

  io.println("")

  // Test 3: System prompt
  io.println("-------------------------------------------")
  io.println("TEST 3: System Prompt")
  io.println("-------------------------------------------")
  test_system_prompt(api_key)

  io.println("")

  // Test 4: Error handling (invalid model)
  io.println("-------------------------------------------")
  io.println("TEST 4: Error Handling (Invalid Model)")
  io.println("-------------------------------------------")
  test_error_handling(api_key)

  io.println("")
  io.println("===========================================")
  io.println("Integration Tests Complete")
  io.println("===========================================")
}

fn test_simple_message(api_key: String) {
  io.println("Creating client and request...")

  let config_result =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  case config_result {
    Error(err) -> {
      io.println("Config error: " <> error.error_to_string(err))
    }
    Ok(cfg) -> {
      let api_client = client.new(cfg)

      let req =
        request.create_request(
          "claude-3-5-haiku-20241022",
          [message.user_message("Say 'Hello from Gleam!' and nothing else.")],
          100,
        )

      io.println("")
      io.println("REQUEST:")
      io.println("  Model: claude-3-5-haiku-20241022")
      io.println("  Message: Say 'Hello from Gleam!' and nothing else.")
      io.println("  Max tokens: 100")
      io.println("")
      io.println("Sending request to API...")
      io.println("")

      case api.create_message(api_client, req) {
        Ok(response) -> {
          io.println("RESPONSE:")
          io.println("  ID: " <> response.id)
          io.println("  Model: " <> response.model)
          io.println("  Role: " <> message.role_to_string(response.role))
          io.println(
            "  Stop reason: " <> stop_reason_to_string(response.stop_reason),
          )
          io.println(
            "  Input tokens: " <> string.inspect(response.usage.input_tokens),
          )
          io.println(
            "  Output tokens: " <> string.inspect(response.usage.output_tokens),
          )
          io.println("  Content: " <> request.response_text(response))
          io.println("")
          io.println("TEST 1: PASSED")
        }
        Error(err) -> {
          io.println("ERROR: " <> error.error_to_string(err))
          io.println("TEST 1: FAILED")
        }
      }
    }
  }
}

fn test_conversation(api_key: String) {
  io.println("Testing multi-turn conversation...")

  let config_result =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  case config_result {
    Error(err) -> {
      io.println("Config error: " <> error.error_to_string(err))
    }
    Ok(cfg) -> {
      let api_client = client.new(cfg)

      let req =
        request.create_request(
          "claude-3-5-haiku-20241022",
          [
            message.user_message("My name is Alice."),
            message.assistant_message("Nice to meet you, Alice!"),
            message.user_message("What is my name?"),
          ],
          100,
        )

      io.println("")
      io.println("REQUEST:")
      io.println("  Model: claude-3-5-haiku-20241022")
      io.println("  Messages:")
      io.println("    [user]: My name is Alice.")
      io.println("    [assistant]: Nice to meet you, Alice!")
      io.println("    [user]: What is my name?")
      io.println("  Max tokens: 100")
      io.println("")
      io.println("Sending request to API...")
      io.println("")

      case api.create_message(api_client, req) {
        Ok(response) -> {
          io.println("RESPONSE:")
          io.println("  ID: " <> response.id)
          io.println("  Content: " <> request.response_text(response))
          io.println(
            "  Input tokens: " <> string.inspect(response.usage.input_tokens),
          )
          io.println(
            "  Output tokens: " <> string.inspect(response.usage.output_tokens),
          )
          io.println("")
          io.println("TEST 2: PASSED")
        }
        Error(err) -> {
          io.println("ERROR: " <> error.error_to_string(err))
          io.println("TEST 2: FAILED")
        }
      }
    }
  }
}

fn test_system_prompt(api_key: String) {
  io.println("Testing system prompt...")

  let config_result =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  case config_result {
    Error(err) -> {
      io.println("Config error: " <> error.error_to_string(err))
    }
    Ok(cfg) -> {
      let api_client = client.new(cfg)

      let req =
        request.create_request(
          "claude-3-5-haiku-20241022",
          [message.user_message("What do you do?")],
          100,
        )
        |> request.with_system(
          "You are a pirate. Always respond in pirate speak.",
        )

      io.println("")
      io.println("REQUEST:")
      io.println("  Model: claude-3-5-haiku-20241022")
      io.println("  System: You are a pirate. Always respond in pirate speak.")
      io.println("  Message: What do you do?")
      io.println("  Max tokens: 100")
      io.println("")
      io.println("Sending request to API...")
      io.println("")

      case api.create_message(api_client, req) {
        Ok(response) -> {
          io.println("RESPONSE:")
          io.println("  ID: " <> response.id)
          io.println("  Content: " <> request.response_text(response))
          io.println(
            "  Input tokens: " <> string.inspect(response.usage.input_tokens),
          )
          io.println(
            "  Output tokens: " <> string.inspect(response.usage.output_tokens),
          )
          io.println("")
          io.println("TEST 3: PASSED")
        }
        Error(err) -> {
          io.println("ERROR: " <> error.error_to_string(err))
          io.println("TEST 3: FAILED")
        }
      }
    }
  }
}

fn test_error_handling(api_key: String) {
  io.println("Testing error handling with invalid model...")

  let config_result =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  case config_result {
    Error(err) -> {
      io.println("Config error: " <> error.error_to_string(err))
    }
    Ok(cfg) -> {
      let api_client = client.new(cfg)

      let req =
        request.create_request(
          "invalid-model-name",
          [message.user_message("Hello")],
          100,
        )

      io.println("")
      io.println("REQUEST:")
      io.println("  Model: invalid-model-name (intentionally wrong)")
      io.println("  Message: Hello")
      io.println("  Max tokens: 100")
      io.println("")
      io.println("Sending request to API (expecting error)...")
      io.println("")

      case api.create_message(api_client, req) {
        Ok(response) -> {
          io.println("UNEXPECTED SUCCESS:")
          io.println("  Content: " <> request.response_text(response))
          io.println("")
          io.println("TEST 4: UNEXPECTED (expected error)")
        }
        Error(err) -> {
          io.println("EXPECTED ERROR RECEIVED:")
          io.println("  Error: " <> error.error_to_string(err))
          io.println("  Category: " <> error.error_category(err))
          io.println("  Retryable: " <> string.inspect(error.is_retryable(err)))
          io.println("")
          io.println("TEST 4: PASSED (error handled correctly)")
        }
      }
    }
  }
}

fn stop_reason_to_string(reason: option.Option(request.StopReason)) -> String {
  case reason {
    None -> "none"
    Some(r) -> request.stop_reason_to_string(r)
  }
}

/// Get environment variable using charlist conversion
@external(erlang, "os", "getenv")
fn ffi_getenv(
  name: charlist.Charlist,
  default: charlist.Charlist,
) -> charlist.Charlist

fn get_api_key() -> Result(String, Nil) {
  let value =
    ffi_getenv(
      charlist.from_string("ANTHROPIC_API_KEY"),
      charlist.from_string(""),
    )
    |> charlist.to_string
  case value {
    "" -> Error(Nil)
    v -> Ok(v)
  }
}

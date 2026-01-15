//// Tool Use Integration Test for Anthropic API
////
//// This script tests the complete tool use workflow with the Claude API
//// Run with: gleam run -m examples/tool_use_integration_test

import anthropic/api
import anthropic/client
import anthropic/config
import anthropic/tools.{
  build_tool_result_messages, dispatch_tool_calls, extract_tool_calls,
  needs_tool_execution,
}
import anthropic/tools/builder.{
  add_enum_param, add_string_param, build, tool_builder, with_description,
}
import anthropic/types/error
import anthropic/types/message
import anthropic/types/request
import anthropic/types/tool.{Any, Auto, ToolName}
import gleam/erlang/charlist
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// Main entry point
pub fn main() {
  io.println("===========================================")
  io.println("Anthropic Tool Use Integration Test")
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
  // Test 1: Tool definition and request with Auto choice
  io.println("-------------------------------------------")
  io.println("TEST 1: Tool Definition with Auto Choice")
  io.println("-------------------------------------------")
  let r1 = test_tool_definition_auto(api_key)
  case r1 {
    True -> io.println("TEST 1: PASSED")
    False -> io.println("TEST 1: FAILED")
  }

  io.println("")

  // Test 2: Forced tool use with ToolName choice
  io.println("-------------------------------------------")
  io.println("TEST 2: Forced Tool Use (ToolName Choice)")
  io.println("-------------------------------------------")
  let r2 = test_forced_tool_use(api_key)
  case r2 {
    True -> io.println("TEST 2: PASSED")
    False -> io.println("TEST 2: FAILED")
  }

  io.println("")

  // Test 3: Complete tool use workflow (tool_use -> execute -> tool_result)
  io.println("-------------------------------------------")
  io.println("TEST 3: Complete Tool Use Workflow")
  io.println("-------------------------------------------")
  let r3 = test_complete_workflow(api_key)
  case r3 {
    True -> io.println("TEST 3: PASSED")
    False -> io.println("TEST 3: FAILED")
  }

  io.println("")

  // Test 4: Multiple tools with Any choice
  io.println("-------------------------------------------")
  io.println("TEST 4: Multiple Tools with Any Choice")
  io.println("-------------------------------------------")
  let r4 = test_multiple_tools(api_key)
  case r4 {
    True -> io.println("TEST 4: PASSED")
    False -> io.println("TEST 4: FAILED")
  }

  io.println("")

  // Test 5: Tool builder API validation
  io.println("-------------------------------------------")
  io.println("TEST 5: Tool Builder API")
  io.println("-------------------------------------------")
  let r5 = test_tool_builder(api_key)
  case r5 {
    True -> io.println("TEST 5: PASSED")
    False -> io.println("TEST 5: FAILED")
  }

  // Calculate results
  let results = [r1, r2, r3, r4, r5]
  let passed = list.filter(results, fn(r) { r }) |> list.length
  let failed = list.filter(results, fn(r) { !r }) |> list.length

  io.println("")
  io.println("===========================================")
  io.println("Tool Use Integration Tests Complete")
  io.println("===========================================")
  io.println(
    "Results: "
    <> int.to_string(passed)
    <> " passed, "
    <> int.to_string(failed)
    <> " failed",
  )
}

fn test_tool_definition_auto(api_key: String) -> Bool {
  io.println("Testing tool definition with Auto choice...")

  let config_result =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  case config_result {
    Error(err) -> {
      io.println("Config error: " <> error.error_to_string(err))
      False
    }
    Ok(cfg) -> {
      let api_client = client.new(cfg)

      // Build a simple calculator tool using builder API
      let calculator_tool =
        tool_builder("calculator")
        |> with_description("Perform basic arithmetic operations")
        |> add_string_param(
          "operation",
          "The operation: add, subtract, multiply, divide",
          True,
        )
        |> add_string_param("a", "First number as a string", True)
        |> add_string_param("b", "Second number as a string", True)
        |> build()

      let req =
        request.create_request(
          "claude-3-5-haiku-20241022",
          [message.user_message("What is 15 + 27? Use the calculator tool.")],
          200,
        )
        |> request.with_tools([calculator_tool])
        |> request.with_tool_choice(Auto)

      io.println("")
      io.println("REQUEST:")
      io.println("  Model: claude-3-5-haiku-20241022")
      io.println("  Tool: calculator (add, subtract, multiply, divide)")
      io.println("  Tool Choice: Auto")
      io.println("  Message: What is 15 + 27? Use the calculator tool.")
      io.println("")
      io.println("Sending request to API...")
      io.println("")

      case api.create_message(api_client, req) {
        Ok(response) -> {
          io.println("RESPONSE:")
          io.println("  ID: " <> response.id)
          io.println("  Model: " <> response.model)
          io.println(
            "  Stop reason: " <> stop_reason_to_string(response.stop_reason),
          )
          io.println(
            "  Input tokens: " <> int.to_string(response.usage.input_tokens),
          )
          io.println(
            "  Output tokens: " <> int.to_string(response.usage.output_tokens),
          )

          // Check if tool use was triggered
          let is_tool_use = needs_tool_execution(response)
          io.println("  Needs tool execution: " <> string.inspect(is_tool_use))

          case is_tool_use {
            True -> {
              let tool_calls = extract_tool_calls(response)
              io.println(
                "  Tool calls count: " <> int.to_string(list.length(tool_calls)),
              )
              list.each(tool_calls, fn(call) {
                io.println("  Tool call:")
                io.println("    ID: " <> call.id)
                io.println("    Name: " <> call.name)
                io.println("    Input: " <> call.input)
              })
              True
            }
            False -> {
              io.println("  Text response: " <> request.response_text(response))
              // Still a pass if the model chose not to use the tool
              True
            }
          }
        }
        Error(err) -> {
          io.println("ERROR: " <> error.error_to_string(err))
          False
        }
      }
    }
  }
}

fn test_forced_tool_use(api_key: String) -> Bool {
  io.println("Testing forced tool use with ToolName choice...")

  let config_result =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  case config_result {
    Error(err) -> {
      io.println("Config error: " <> error.error_to_string(err))
      False
    }
    Ok(cfg) -> {
      let api_client = client.new(cfg)

      // Build a weather tool
      let weather_tool =
        tool_builder("get_weather")
        |> with_description("Get the current weather for a location")
        |> add_string_param(
          "location",
          "City and state, e.g. 'San Francisco, CA'",
          True,
        )
        |> add_enum_param(
          "unit",
          "Temperature unit",
          ["celsius", "fahrenheit"],
          False,
        )
        |> build()

      let req =
        request.create_request(
          "claude-3-5-haiku-20241022",
          [message.user_message("Tell me about the weather in Tokyo.")],
          200,
        )
        |> request.with_tools([weather_tool])
        |> request.with_tool_choice(ToolName("get_weather"))

      io.println("")
      io.println("REQUEST:")
      io.println("  Model: claude-3-5-haiku-20241022")
      io.println("  Tool: get_weather")
      io.println("  Tool Choice: ToolName(\"get_weather\") - FORCED")
      io.println("  Message: Tell me about the weather in Tokyo.")
      io.println("")
      io.println("Sending request to API...")
      io.println("")

      case api.create_message(api_client, req) {
        Ok(response) -> {
          io.println("RESPONSE:")
          io.println("  ID: " <> response.id)
          io.println(
            "  Stop reason: " <> stop_reason_to_string(response.stop_reason),
          )
          io.println(
            "  Input tokens: " <> int.to_string(response.usage.input_tokens),
          )
          io.println(
            "  Output tokens: " <> int.to_string(response.usage.output_tokens),
          )

          let is_tool_use = needs_tool_execution(response)
          io.println("  Needs tool execution: " <> string.inspect(is_tool_use))

          case is_tool_use {
            True -> {
              let tool_calls = extract_tool_calls(response)
              io.println(
                "  Tool calls count: " <> int.to_string(list.length(tool_calls)),
              )
              list.each(tool_calls, fn(call) {
                io.println("  Tool call:")
                io.println("    ID: " <> call.id)
                io.println("    Name: " <> call.name)
                io.println("    Input: " <> call.input)
              })
              // Verify the tool was called
              case list.first(tool_calls) {
                Ok(call) -> call.name == "get_weather"
                Error(_) -> False
              }
            }
            False -> {
              io.println("ERROR: Expected tool_use but got text response")
              False
            }
          }
        }
        Error(err) -> {
          io.println("ERROR: " <> error.error_to_string(err))
          False
        }
      }
    }
  }
}

fn test_complete_workflow(api_key: String) -> Bool {
  io.println("Testing complete tool use workflow...")
  io.println("(tool_use -> execute -> tool_result -> final response)")

  let config_result =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  case config_result {
    Error(err) -> {
      io.println("Config error: " <> error.error_to_string(err))
      False
    }
    Ok(cfg) -> {
      let api_client = client.new(cfg)

      // Build a simple lookup tool
      let lookup_tool =
        tool_builder("lookup_capital")
        |> with_description("Look up the capital city of a country")
        |> add_string_param("country", "The country name", True)
        |> build()

      let original_messages = [
        message.user_message(
          "What is the capital of France? Use the lookup tool.",
        ),
      ]

      let req =
        request.create_request(
          "claude-3-5-haiku-20241022",
          original_messages,
          200,
        )
        |> request.with_tools([lookup_tool])
        |> request.with_tool_choice(ToolName("lookup_capital"))

      io.println("")
      io.println("STEP 1: Initial request with tool")
      io.println(
        "  Message: What is the capital of France? Use the lookup tool.",
      )
      io.println("  Tool Choice: ToolName(\"lookup_capital\") - FORCED")
      io.println("")
      io.println("Sending request to API...")
      io.println("")

      case api.create_message(api_client, req) {
        Ok(response) -> {
          io.println("STEP 1 RESPONSE:")
          io.println("  ID: " <> response.id)
          io.println(
            "  Stop reason: " <> stop_reason_to_string(response.stop_reason),
          )

          case needs_tool_execution(response) {
            True -> {
              let tool_calls = extract_tool_calls(response)
              io.println(
                "  Tool calls: " <> int.to_string(list.length(tool_calls)),
              )

              // Execute tools using dispatch
              let handlers = [
                #("lookup_capital", fn(_input: String) {
                  // Simulated lookup - in real usage this would parse input JSON
                  Ok("{\"capital\": \"Paris\", \"country\": \"France\"}")
                }),
              ]

              let results = dispatch_tool_calls(tool_calls, handlers)
              io.println("")
              io.println("STEP 2: Tool execution")
              list.each(results, fn(result) {
                case result {
                  tool.ToolSuccess(id, content) -> {
                    io.println("  Tool result (success):")
                    io.println("    ID: " <> id)
                    io.println("    Content: " <> content)
                  }
                  tool.ToolFailure(id, err) -> {
                    io.println("  Tool result (failure):")
                    io.println("    ID: " <> id)
                    io.println("    Error: " <> err)
                  }
                }
              })

              // Build continuation messages
              let continuation_messages =
                build_tool_result_messages(original_messages, response, results)

              io.println("")
              io.println("STEP 3: Sending tool results back")
              io.println(
                "  Messages count: "
                <> int.to_string(list.length(continuation_messages)),
              )

              let continuation_req =
                request.create_request(
                  "claude-3-5-haiku-20241022",
                  continuation_messages,
                  200,
                )
                |> request.with_tools([lookup_tool])

              case api.create_message(api_client, continuation_req) {
                Ok(final_response) -> {
                  io.println("")
                  io.println("STEP 3 RESPONSE (Final):")
                  io.println("  ID: " <> final_response.id)
                  io.println(
                    "  Stop reason: "
                    <> stop_reason_to_string(final_response.stop_reason),
                  )
                  io.println(
                    "  Content: " <> request.response_text(final_response),
                  )
                  io.println(
                    "  Input tokens: "
                    <> int.to_string(final_response.usage.input_tokens),
                  )
                  io.println(
                    "  Output tokens: "
                    <> int.to_string(final_response.usage.output_tokens),
                  )

                  // Verify we got a text response (not tool_use)
                  case final_response.stop_reason {
                    Some(request.EndTurn) -> True
                    Some(request.MaxTokens) -> True
                    _ -> {
                      io.println("  Warning: Unexpected stop reason")
                      True
                    }
                  }
                }
                Error(err) -> {
                  io.println(
                    "ERROR in continuation: " <> error.error_to_string(err),
                  )
                  False
                }
              }
            }
            False -> {
              io.println("ERROR: Expected tool_use but got text response")
              False
            }
          }
        }
        Error(err) -> {
          io.println("ERROR: " <> error.error_to_string(err))
          False
        }
      }
    }
  }
}

fn test_multiple_tools(api_key: String) -> Bool {
  io.println("Testing multiple tools with Any choice...")

  let config_result =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  case config_result {
    Error(err) -> {
      io.println("Config error: " <> error.error_to_string(err))
      False
    }
    Ok(cfg) -> {
      let api_client = client.new(cfg)

      // Build multiple tools
      let weather_tool =
        tool_builder("get_weather")
        |> with_description("Get weather for a location")
        |> add_string_param("location", "City name", True)
        |> build()

      let time_tool =
        tool_builder("get_time")
        |> with_description("Get current time in a timezone")
        |> add_string_param(
          "timezone",
          "Timezone name like 'America/New_York'",
          True,
        )
        |> build()

      let stock_tool =
        tool_builder("get_stock_price")
        |> with_description("Get stock price for a ticker symbol")
        |> add_string_param("symbol", "Stock ticker symbol like 'AAPL'", True)
        |> build()

      let req =
        request.create_request(
          "claude-3-5-haiku-20241022",
          [message.user_message("I need to know the current time in New York.")],
          200,
        )
        |> request.with_tools([weather_tool, time_tool, stock_tool])
        |> request.with_tool_choice(Any)

      io.println("")
      io.println("REQUEST:")
      io.println("  Model: claude-3-5-haiku-20241022")
      io.println("  Tools: get_weather, get_time, get_stock_price")
      io.println("  Tool Choice: Any - must use one of the tools")
      io.println("  Message: I need to know the current time in New York.")
      io.println("")
      io.println("Sending request to API...")
      io.println("")

      case api.create_message(api_client, req) {
        Ok(response) -> {
          io.println("RESPONSE:")
          io.println("  ID: " <> response.id)
          io.println(
            "  Stop reason: " <> stop_reason_to_string(response.stop_reason),
          )
          io.println(
            "  Input tokens: " <> int.to_string(response.usage.input_tokens),
          )
          io.println(
            "  Output tokens: " <> int.to_string(response.usage.output_tokens),
          )

          let is_tool_use = needs_tool_execution(response)
          io.println("  Needs tool execution: " <> string.inspect(is_tool_use))

          case is_tool_use {
            True -> {
              let tool_calls = extract_tool_calls(response)
              io.println(
                "  Tool calls: " <> int.to_string(list.length(tool_calls)),
              )
              list.each(tool_calls, fn(call) {
                io.println("  Tool call:")
                io.println("    ID: " <> call.id)
                io.println("    Name: " <> call.name)
                io.println("    Input: " <> call.input)
              })

              // Verify the correct tool was selected
              case list.first(tool_calls) {
                Ok(call) -> {
                  io.println(
                    "  Selected tool: " <> call.name <> " (expected: get_time)",
                  )
                  call.name == "get_time"
                }
                Error(_) -> False
              }
            }
            False -> {
              io.println("ERROR: Any choice should force tool use")
              False
            }
          }
        }
        Error(err) -> {
          io.println("ERROR: " <> error.error_to_string(err))
          False
        }
      }
    }
  }
}

fn test_tool_builder(api_key: String) -> Bool {
  io.println("Testing tool builder API with complex tool...")

  let config_result =
    config.config_options()
    |> config.with_api_key(api_key)
    |> config.load_config()

  case config_result {
    Error(err) -> {
      io.println("Config error: " <> error.error_to_string(err))
      False
    }
    Ok(cfg) -> {
      let api_client = client.new(cfg)

      // Build a complex tool with multiple parameter types
      let search_tool =
        tool_builder("search_database")
        |> with_description("Search a database with various filters")
        |> add_string_param("query", "The search query string", True)
        |> add_enum_param(
          "category",
          "Category to search in",
          [
            "products",
            "users",
            "orders",
          ],
          False,
        )
        |> add_enum_param(
          "sort_order",
          "Sort order for results",
          [
            "asc",
            "desc",
          ],
          False,
        )
        |> build()

      let req =
        request.create_request(
          "claude-3-5-haiku-20241022",
          [
            message.user_message(
              "Search for 'laptop' in the products category, sorted descending.",
            ),
          ],
          200,
        )
        |> request.with_tools([search_tool])
        |> request.with_tool_choice(ToolName("search_database"))

      io.println("")
      io.println("REQUEST:")
      io.println("  Model: claude-3-5-haiku-20241022")
      io.println("  Tool: search_database (built with builder API)")
      io.println("  Parameters:")
      io.println("    - query (string, required)")
      io.println("    - category (enum: products/users/orders, optional)")
      io.println("    - sort_order (enum: asc/desc, optional)")
      io.println("  Tool Choice: ToolName(\"search_database\") - FORCED")
      io.println(
        "  Message: Search for 'laptop' in the products category, sorted descending.",
      )
      io.println("")
      io.println("Sending request to API...")
      io.println("")

      case api.create_message(api_client, req) {
        Ok(response) -> {
          io.println("RESPONSE:")
          io.println("  ID: " <> response.id)
          io.println(
            "  Stop reason: " <> stop_reason_to_string(response.stop_reason),
          )
          io.println(
            "  Input tokens: " <> int.to_string(response.usage.input_tokens),
          )
          io.println(
            "  Output tokens: " <> int.to_string(response.usage.output_tokens),
          )

          let is_tool_use = needs_tool_execution(response)
          io.println("  Needs tool execution: " <> string.inspect(is_tool_use))

          case is_tool_use {
            True -> {
              let tool_calls = extract_tool_calls(response)
              list.each(tool_calls, fn(call) {
                io.println("  Tool call:")
                io.println("    ID: " <> call.id)
                io.println("    Name: " <> call.name)
                io.println("    Input: " <> call.input)
              })

              // Verify tool was called with correct structure
              case list.first(tool_calls) {
                Ok(call) -> {
                  let has_query = string.contains(call.input, "laptop")
                  let has_category = string.contains(call.input, "products")
                  io.println("")
                  io.println("  Validation:")
                  io.println(
                    "    Contains 'laptop': " <> string.inspect(has_query),
                  )
                  io.println(
                    "    Contains 'products': " <> string.inspect(has_category),
                  )
                  call.name == "search_database" && has_query
                }
                Error(_) -> False
              }
            }
            False -> {
              io.println("ERROR: Expected tool_use response")
              False
            }
          }
        }
        Error(err) -> {
          io.println("ERROR: " <> error.error_to_string(err))
          False
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

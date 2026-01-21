//// # Anthropic Gleam
////
//// A well-typed, idiomatic Gleam client for Anthropic's Claude API with
//// streaming support and tool use.
////
//// ## Quick Start
////
//// ```gleam
//// import anthropic/api
//// import anthropic/client
//// import anthropic/config
//// import anthropic/types/error
//// import anthropic/types/message
//// import anthropic/types/request
//// import gleam/io
////
//// pub fn main() {
////   // Load configuration (reads ANTHROPIC_API_KEY from environment)
////   let assert Ok(cfg) = config.config_options() |> config.load_config()
////
////   // Create client
////   let api_client = client.new(cfg)
////
////   // Create a request
////   let req = request.create_request(
////     "claude-sonnet-4-20250514",
////     [message.user_message("Hello, Claude!")],
////     1024,
////   )
////
////   // Send the request
////   case api.create_message(api_client, req) {
////     Ok(response) -> io.println(request.response_text(response))
////     Error(err) -> io.println("Error: " <> error.error_to_string(err))
////   }
//// }
//// ```
////
//// ## Sans-IO Pattern (Any HTTP Client)
////
//// This library supports a sans-io architecture, allowing you to use any
//// HTTP client. Build requests and parse responses without HTTP dependencies:
////
//// ```gleam
//// import anthropic/http
//// import anthropic/types/message
//// import anthropic/types/request
////
//// // Build the request
//// let req = request.create_request(
////   "claude-sonnet-4-20250514",
////   [message.user_message("Hello!")],
////   1024,
//// )
//// let http_request = http.build_messages_request(api_key, base_url, req)
////
//// // Send with YOUR HTTP client (hackney, httpc, fetch on JS, etc.)
//// let http_response = my_http_client.send(http_request)
////
//// // Parse the response
//// case http.parse_messages_response(http_response) {
////   Ok(response) -> request.response_text(response)
////   Error(err) -> error.error_to_string(err)
//// }
//// ```
////
//// ## Real-Time Streaming (Sans-IO)
////
//// For true real-time streaming where you process events as they arrive:
////
//// ```gleam
//// import anthropic/http
//// import anthropic/streaming/handler.{
////   new_streaming_state, process_chunk, finalize_stream, get_event_text
//// }
//// import anthropic/types/message
//// import anthropic/types/request
////
//// // Build streaming request
//// let req = request.create_request(
////   "claude-sonnet-4-20250514",
////   [message.user_message("Write a poem")],
////   1024,
//// )
//// let http_request = http.build_streaming_request(api_key, base_url, req)
////
//// // Initialize streaming state
//// let state = new_streaming_state()
////
//// // As each chunk arrives from your streaming HTTP client:
//// let #(events, new_state) = process_chunk(state, chunk)
////
//// // Handle events in real-time
//// list.each(events, fn(event) {
////   case get_event_text(event) {
////     Ok(text) -> io.print(text)  // Print immediately!
////     Error(_) -> Nil
////   }
//// })
////
//// // When stream ends, finalize to get any remaining events
//// let final_events = finalize_stream(final_state)
//// ```
////
//// ## Tool Use
////
//// Define tools and handle tool calls:
////
//// ```gleam
//// import anthropic/tools/builder.{
////   tool_builder, with_description, add_string_param, build
//// }
//// import anthropic/tools.{
////   needs_tool_execution, extract_tool_calls, dispatch_tool_calls
//// }
//// import anthropic/types/tool.{auto_choice, tool_success}
//// import anthropic/types/request.{with_tools, with_tool_choice}
////
//// // Define a tool
//// let weather_tool = tool_builder("get_weather")
////   |> with_description("Get weather for a location")
////   |> add_string_param("location", "City name", True)
////   |> build()
////
//// // Add to request
//// let req = request.create_request(model, messages, max_tokens)
////   |> with_tools([weather_tool])
////   |> with_tool_choice(auto_choice())
////
//// // Handle tool calls
//// case api.create_message(api_client, req) {
////   Ok(response) -> {
////     case needs_tool_execution(response) {
////       True -> {
////         let calls = extract_tool_calls(response)
////         let handlers = [
////           #("get_weather", fn(_input) {
////             tool_success("{\"temp\": 72}")
////           }),
////         ]
////         let results = dispatch_tool_calls(calls, handlers)
////         // Continue conversation with results...
////       }
////       False -> Ok(response)
////     }
////   }
////   Error(err) -> Error(err)
//// }
//// ```
////
//// ## Error Handling
////
//// ```gleam
//// import anthropic/types/error.{
////   is_retryable, is_rate_limit_error, is_authentication_error, error_to_string
//// }
////
//// case api.create_message(api_client, request) {
////   Ok(response) -> handle_success(response)
////   Error(err) -> {
////     io.println("Error: " <> error_to_string(err))
////
////     case is_retryable(err) {
////       True -> retry_later()
////       False -> {
////         case is_authentication_error(err) {
////           True -> io.println("Check your API key")
////           False -> Nil
////         }
////       }
////     }
////   }
//// }
//// ```
////
//// ## Module Structure
////
//// **Core Modules:**
//// - `anthropic/api` - High-level API functions (create_message)
//// - `anthropic/client` - HTTP client wrapper
//// - `anthropic/config` - Configuration management
//// - `anthropic/http` - Sans-IO HTTP types and builders
////
//// **Type Modules:**
//// - `anthropic/types/message` - Message and content block types
//// - `anthropic/types/request` - Request/response types
//// - `anthropic/types/error` - Error types
//// - `anthropic/types/tool` - Tool definition types
//// - `anthropic/types/streaming` - Streaming event types
////
//// **Streaming Modules:**
//// - `anthropic/streaming/handler` - Stream handling (batch and real-time)
//// - `anthropic/streaming/sse` - SSE parser (low-level)
//// - `anthropic/streaming/decoder` - Event decoder (low-level)
//// - `anthropic/streaming/accumulator` - Stream accumulator
////
//// **Tool Modules:**
//// - `anthropic/tools` - Tool use workflow utilities
//// - `anthropic/tools/builder` - Fluent tool builder
////
//// **Utility Modules:**
//// - `anthropic/retry` - Retry logic with exponential backoff
//// - `anthropic/validation` - Request validation
//// - `anthropic/hooks` - Logging and telemetry hooks
//// - `anthropic/testing` - Mock responses for testing

// This module intentionally has no exports.
// Import from the specific modules you need.
// This follows idiomatic Gleam design: small, focused modules with clear APIs.

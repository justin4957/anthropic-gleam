//// Anthropic Gleam - A typed Gleam client for Anthropic's Claude API
////
//// This is the main entry point for the library. Import types and functions
//// from the specific modules that you need:
////
//// ## Quick Start (HTTP-Integrated)
////
//// ```gleam
//// import anthropic/api
//// import anthropic/client
//// import anthropic/config
//// import anthropic/types/message
//// import anthropic/types/request
////
//// let assert Ok(cfg) = config.load_config(config.config_options())
//// let c = client.new(cfg)
//// let req = request.create_request(
////   "claude-sonnet-4-20250514",
////   [message.user_message("Hello!")],
////   1024,
//// )
//// case api.create_message(c, req) {
////   Ok(response) -> request.response_text(response)
////   Error(err) -> error.error_to_string(err)
//// }
//// ```
////
//// ## Sans-IO Pattern (Any HTTP Client)
////
//// ```gleam
//// import anthropic/http
//// import anthropic/types/message
//// import anthropic/types/request
////
//// let req = request.create_request(
////   "claude-sonnet-4-20250514",
////   [message.user_message("Hello!")],
////   1024,
//// )
//// let http_req = http.build_messages_request(api_key, base_url, req)
////
//// // Send with YOUR HTTP client (hackney, httpc, fetch, etc.)
//// let http_response = my_client.send(http_req)
////
//// case http.parse_messages_response(http_response) {
////   Ok(response) -> request.response_text(response)
////   Error(err) -> error.error_to_string(err)
//// }
//// ```
////
//// ## Module Structure
////
//// - `anthropic/api` - High-level API functions (create_message)
//// - `anthropic/client` - HTTP client wrapper
//// - `anthropic/config` - Configuration management
//// - `anthropic/http` - Sans-IO HTTP types and builders
//// - `anthropic/types/message` - Message and content block types
//// - `anthropic/types/request` - Request/response types
//// - `anthropic/types/error` - Error types
//// - `anthropic/types/tool` - Tool definition types
//// - `anthropic/types/streaming` - Streaming event types
//// - `anthropic/streaming/sse` - SSE parser
//// - `anthropic/streaming/decoder` - Event decoder
//// - `anthropic/streaming/accumulator` - Stream accumulator
//// - `anthropic/streaming/handler` - Stream handling utilities
//// - `anthropic/testing` - Mock responses for testing

// This module intentionally has no exports.
// Import from the specific modules you need.
// This follows idiomatic Gleam design: small, focused modules with clear APIs.

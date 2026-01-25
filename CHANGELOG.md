# Changelog

All notable changes to anthropic_gleam will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-01-25

### Fixed

- Response decoder now correctly handles optional `stop_sequence` field when missing from JSON responses (#53, PR #56)
- `mock_text_response_body` and `mock_tool_use_response_body` now include `stop_sequence` field for proper parsing (#54, PR #57)

### Changed

- Updated main module documentation to use current module paths (`anthropic/request` instead of `anthropic/types/request`) (#55, PR #58)
- Updated documentation examples to use new API functions (`api.chat` instead of `api.create_message`, `request.new` instead of `request.create_request`)
- Updated tool handler signature examples to match current API

### Deprecated

- `api.create_message()` - use `api.chat()` instead
- `request.create_request()` - use `request.new()` instead
- `handler.stream_message()` - use `api.chat_stream()` instead
- `handler.stream_message_with_callback()` - use `api.chat_stream_with_callback()` instead

## [0.1.0] - 2026-01-14

### Added

- Complete Messages API support with typed interfaces
- Streaming responses with real-time event handling
- Tool use capabilities
- Automatic retry logic with exponential backoff
- Request validation
- Type-safe error handling
- Comprehensive test suite
- Full API documentation

[Unreleased]: https://github.com/justin4957/anthropic-gleam/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/justin4957/anthropic-gleam/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/justin4957/anthropic-gleam/releases/tag/v0.1.0

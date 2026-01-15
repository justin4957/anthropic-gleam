# Contributing to anthropic_gleam

Thank you for your interest in contributing to anthropic_gleam! This guide will help you get started.

## Development Setup

### Prerequisites

- [Gleam](https://gleam.run/) v1.0 or later
- [Erlang/OTP](https://www.erlang.org/) 26 or later
- An Anthropic API key for integration testing

### Getting Started

1. Clone the repository:
   ```sh
   git clone https://github.com/justin4957/foil.git
   cd foil/packages/anthropic_gleam
   ```

2. Install dependencies:
   ```sh
   gleam deps download
   ```

3. Build the project:
   ```sh
   gleam build
   ```

4. Run tests:
   ```sh
   gleam test
   ```

## Project Structure

```
src/
  anthropic/
    api.gleam           # Core API functions
    client.gleam        # HTTP client
    config.gleam        # Configuration management
    hooks.gleam         # Logging/telemetry hooks
    retry.gleam         # Retry logic
    testing.gleam       # Test utilities
    tools.gleam         # Tool use utilities
    validation.gleam    # Request validation
    streaming/
      events.gleam      # Streaming event types
      parser.gleam      # SSE parser
      stream.gleam      # Streaming API
    tools/
      builder.gleam     # Tool builder API
    types/
      error.gleam       # Error types
      message.gleam     # Message types
      request.gleam     # Request/response types
      tool.gleam        # Tool types
  examples/
    integration_test.gleam        # API integration tests
    tool_use_integration_test.gleam  # Tool use tests
test/
  anthropic_gleam_test.gleam  # Unit tests
```

## Coding Guidelines

### Style

- Follow [Gleam's style guide](https://gleam.run/writing-gleam/)
- Use descriptive variable and function names
- Add documentation comments (`////`) to public functions
- Keep functions small and focused

### Documentation

- All public functions must have documentation comments
- Include usage examples in documentation
- Update the README when adding new features
- Update the CHANGELOG when making changes

### Testing

- Write unit tests for all new functionality
- Tests should be deterministic and not depend on external services
- Use the `anthropic/testing` module for test utilities
- Integration tests should be in `src/examples/`

### Commit Messages

Use conventional commit format:

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `refactor`: Code refactoring
- `chore`: Maintenance tasks

Examples:
```
feat(retry): add exponential backoff with jitter
fix(validation): handle empty tool names correctly
docs(readme): add streaming example
```

## Pull Request Process

1. **Create a branch** from `main`:
   ```sh
   git checkout main
   git pull origin main
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**:
   - Write code
   - Add tests
   - Update documentation

3. **Run checks**:
   ```sh
   gleam build
   gleam test
   gleam format src test
   ```

4. **Commit your changes** following the commit message guidelines

5. **Push and create a PR**:
   ```sh
   git push origin feature/your-feature-name
   ```

6. **Link related issues** in the PR description using `Closes #123`

7. **Wait for CI** to pass and address any feedback

## Running Integration Tests

Integration tests require an API key:

```sh
export ANTHROPIC_API_KEY=sk-ant-...
gleam run -m examples/integration_test
gleam run -m examples/tool_use_integration_test
```

## Reporting Issues

When reporting issues, please include:

- Gleam version (`gleam --version`)
- Erlang/OTP version (`erl -version`)
- Operating system
- Steps to reproduce
- Expected vs actual behavior
- Relevant error messages

## Feature Requests

Feature requests are welcome! Please:

1. Check existing issues first
2. Describe the use case
3. Explain why the feature would be useful
4. Provide example code if possible

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

Open an issue or start a discussion. We're happy to help!

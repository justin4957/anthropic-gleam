# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in anthropic_gleam, please report it responsibly:

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Email the maintainers directly or use GitHub's private vulnerability reporting feature
3. Include as much detail as possible about the vulnerability
4. Allow reasonable time for a fix before public disclosure

## Security Best Practices

When using anthropic_gleam:

### API Key Management

**Never hardcode API keys in your code!**

```gleam
import gleam/erlang/os

// Good: Use environment variables
let api_key = os.get_env("ANTHROPIC_API_KEY")
```

### Additional Recommendations

- Store API keys in environment variables or secure secret management systems
- Never commit API keys to version control
- Use the minimum required permissions for your API key
- Rotate API keys periodically
- Monitor your API usage for unexpected activity

## Acknowledgments

We appreciate security researchers who help keep anthropic_gleam secure through responsible disclosure.

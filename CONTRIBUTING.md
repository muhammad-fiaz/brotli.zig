# Contributing to brotli.zig

Thank you for your interest in contributing to brotli.zig!

## Getting Started

1. Fork the repository
2. Clone your fork
3. Create a feature branch: `git checkout -b my-feature`
4. Make your changes
5. Run tests: `zig build test`
6. Build examples: `zig build examples`
7. Commit and push your changes
8. Open a pull request

## Development

### Prerequisites

- Zig 0.16.0 or later

### Building

```bash
zig build            # Build library
zig build test       # Run unit tests
zig build examples   # Build all examples
```

### Code Style

- Follow idiomatic Zig conventions
- Use the existing code style as reference
- Keep changes minimal and focused
- Add tests for new functionality

### Project Structure

```
src/           # Zig binding layer (your contributions go here)
c/             # Vendored Brotli C source (do not modify)
examples/      # Example programs
```

> **Note:** The `c/` directory contains the upstream Brotli C source. Do not modify it directly. Contributions should be made to the Zig binding layer in `src/`.

## Pull Requests

- Keep PRs focused on a single change
- Include a clear description of what the PR does
- Ensure all tests pass
- Add examples if adding new functionality

## Issues

- Search existing issues before opening a new one
- Include steps to reproduce for bug reports
- Specify your Zig version and platform

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

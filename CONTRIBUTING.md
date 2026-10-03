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

- Zig 0.17.0 or later

### Building

```bash
zig build                  # Build library
zig build test             # Run unit tests and reference interop tests
zig build run-all-examples # Build and execute all examples
zig build fuzz             # Run decoder fuzzing tests
zig build docs             # Generate documentation
```

### Code Style

- Follow idiomatic Zig conventions with camelCase public APIs
- Use the existing code style as reference
- Keep changes minimal and focused
- Add tests for new functionality

### Project Structure

```
src/           # 100% Native Zig Brotli codec implementation
examples/      # Example programs
docs/          # VitePress documentation site
```

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

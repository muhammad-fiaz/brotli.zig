---
title: Examples
description: Runnable examples covering every brotli.zig feature.
---

# Examples

All examples are standalone executables registered as build steps.

| Example | File | Description |
|---------|------|-------------|
| `compress_file` | `examples/compress_file.zig` | One-shot compression across quality levels with round-trip verification |
| `streaming_compression` | `examples/streaming_compression.zig` | 4 MiB chunked streaming compression with progress callback |
| `decompress_file` | `examples/decompress_file.zig` | Basic decompression with verification |
| `streaming_decompression` | `examples/streaming_decompression.zig` | Chunked decompression via `feed`/`take` |
| `dictionary_compression` | `examples/dictionary_compression.zig` | Shared-dictionary round trip (plain decode fails without it!) |
| `reusable_context` | `examples/reusable_context.zig` | Multiple streams on one encoder/decoder context |
| `error_handling` | `examples/error_handling.zig` | Corruption, truncation, and detailed error codes |
| `format_introspection` | `examples/format_introspection.zig` | Version, quality/window bounds, format constants |
| `bit_level` | `examples/bit_level.zig` | Low-level bit reader/writer primitives |

## Run

```bash
zig build run-compress_file
zig build run-streaming_compression
zig build run-decompress_file
zig build run-streaming_decompression
zig build run-dictionary_compression
zig build run-reusable_context
zig build run-error_handling
zig build run-format_introspection
zig build run-bit_level

# everything at once
zig build run-all-examples
```

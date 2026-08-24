---
title: API Reference
description: Complete brotli.zig API surface.
---

# API Reference

## One-Shot Functions

### `compress`

```zig
pub fn compress(allocator: std.mem.Allocator, input: []const u8) ![]u8
```

One-shot compression with default options (quality 11, window 22).

### `compressWithOptions`

```zig
pub fn compressWithOptions(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: CompressionOptions,
) ![]u8
```

Full control: quality (0â€“11), lgwin (10â€“24), mode, size hint, progress
callback. See [CompressionOptions](./compress-options).

### `decompress`

```zig
pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8
```

One-shot decompression into a freshly allocated buffer.

### `decompressWithOptions`

```zig
pub fn decompressWithOptions(allocator, input, options: DecoderOptions) ![]u8
```

Decoder options include `large_window` for LGWIN up to 30.

### `decompressInto`

```zig
pub fn decompressInto(allocator, input: []const u8, output: []u8) !usize
```

Decompress into a caller-provided buffer; returns bytes written.

### `maxCompressedSize`

```zig
pub fn maxCompressedSize(input_size: usize) usize
```

Upper bound for output allocation (mirrors `BrotliEncoderMaxCompressedSize`).

## Types

| Type | Definition | Docs |
|------|------------|------|
| `Encoder` | `src/compress/encode.zig` | [Encoder](/api/compressor) |
| `Decoder` | `src/decompress/decode.zig` | [Decoder](/api/decompressor) |
| `StreamingCompressor` | `src/compress/encode.zig` | [StreamCompressor](/api/stream-compressor) |
| `StreamingDecompressor` | `src/brotli.zig` | [StreamDecompressor](/api/stream-decompressor) |
| `CompressionOptions` | `src/compress/encode.zig` | [Options](/api/compress-options) |
| `DecoderOptions` | `src/decompress/decode.zig` | [Options](/api/decompress-options) |
| `Dictionaries` | `src/dictionary/dictionary.zig` + attach APIs | [Dict](/api/dict) |
| `ErrorCode` / `DecodeResult` | `src/decompress/decode.zig` | [Errors](/api/errors) |

## Version

```zig
brotli.version        // "0.0.3"
brotli.versionNumber() // 3
brotli.versionString() // "0.0.3"
```

## Constants

Quality/window bounds and format sizes â€” see [Constants](./constants).

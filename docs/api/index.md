---
title: API Reference
description: Complete public API surface for brotli.zig native compression and decompression.
---

# API Reference

`brotli.zig` exposes an idiomatic, camelCase public API facade in `src/brotli.zig`. It delegates to modular codec implementations in `src/compress/`, `src/decompress/`, and `src/streaming/` without overhead.

## One-Shot Functions

### `compress`

```zig
pub fn compress(allocator: std.mem.Allocator, input: []const u8) ![]u8
```

One-shot compression with default options (`quality = 11`, `lgWin = 22`).
Allocates a slice containing the complete compressed Brotli bitstream; the caller owns the returned slice.

### `compressWithOptions`

```zig
pub fn compressWithOptions(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: CompressionOptions,
) ![]u8
```

One-shot compression with full parameter control: quality (`0..11`), window size (`10..24` standard, up to `30` with `largeWindow = true`), text/font modes, block size hints, distance coding, custom dictionary, and progress callbacks. See [CompressionOptions](/api/compress-options).

### `maxCompressedSize`

```zig
pub fn maxCompressedSize(input_size: usize) usize
```

Calculates an upper bound for compressed output allocation for a given uncompressed size (mirrors RFC 7932 / `BrotliEncoderMaxCompressedSize`). Guaranteed to be sufficient to hold the compressed bitstream.

### `decompress`

```zig
pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8
```

One-shot decompression into a freshly allocated buffer with default options.
The caller owns the returned slice.

### `decompressWithOptions`

```zig
pub fn decompressWithOptions(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: DecompressionOptions,
) ![]u8
```

One-shot decompression with explicit options, including `largeWindow` support (LGWIN up to 30), custom dictionary back-references, and safety limits (`maxOutputSize`, `ringBufferSizeLimit`). See [DecompressionOptions](/api/decompress-options).

### `compressWithSharedDictionary`

```zig
pub fn compressWithSharedDictionary(
    allocator: std.mem.Allocator,
    input: []const u8,
    dict: *const SharedDictionary,
    options: CompressionOptions,
) ![]u8
```

Compresses an input slice referencing a pre-populated compound `SharedDictionary`.

### `decompressWithSharedDictionary`

```zig
pub fn decompressWithSharedDictionary(
    allocator: std.mem.Allocator,
    input: []const u8,
    dict: *const SharedDictionary,
    options: DecompressionOptions,
) ![]u8
```

Decompresses a Brotli bitstream referencing an identical pre-populated compound `SharedDictionary`.

### `decompressInto`

```zig
pub fn decompressInto(
    allocator: std.mem.Allocator,
    input: []const u8,
    output: []u8,
) !usize
```

Decompresses directly into a caller-provided destination slice; returns the exact number of bytes written. Fails with `error.OutputTooSmall` or `error.ResourceLimitExceeded` if the destination slice is insufficient.

### `compressStream`

```zig
pub fn compressStream(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    options: CompressionOptions,
) !void
```

Streams uncompressed data from any Zig `std.Io.Reader` directly to a `std.Io.Writer` using chunked streaming without loading the entire payload into memory.

### `decompressStream`

```zig
pub fn decompressStream(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    options: DecompressionOptions,
) !void
```

Streams compressed Brotli data from a `std.Io.Reader` directly to a `std.Io.Writer`, expanding blocks incrementally.

## Types & Contexts

| Type | Source Module | Documentation |
|---|---|---|
| `Compressor` / `Encoder` | `src/compress/encode.zig` | [Compressor](/api/compressor) |
| `Decompressor` / `Decoder` | `src/decompress/decode.zig` | [Decompressor](/api/decompressor) |
| `StreamingCompressor` | `src/streaming/compressor.zig` | [StreamingCompressor](/api/stream-compressor) |
| `StreamingDecompressor` | `src/streaming/decompressor.zig` | [StreamingDecompressor](/api/stream-decompressor) |
| `SharedDictionary` | `src/common/shared_dictionary.zig` | [Dictionaries](/api/dict) |
| `CompressionOptions` | `src/compress/encode.zig` | [CompressionOptions](/api/compress-options) |
| `DecompressionOptions` | `src/decompress/decode.zig` | [DecompressionOptions](/api/decompress-options) |
| `Error` | `src/brotli.zig` | [Errors](/api/errors) |
| `ErrorCode` / `BrotliErrorInfo` | `src/decompress/decode.zig` | [Errors](/api/errors) |
| `DecodeResult` | `src/decompress/decode.zig` | [Errors](/api/errors) |

## Low-Level Submodules

`brotli.zig` re-exports modular subsystems for fine-grained format inspection and manipulation:

- `brotli.constants`: RFC 7932 format limits and constants (see [Constants](/api/constants)).
- `brotli.context`: Context modeling formulas and lookup tables.
- `brotli.transform`: Word transformations for static dictionary entries.
- `brotli.Dictionary`: Static dictionary binary and lookup operations (see [Dictionaries](/api/dict)).
- `brotli.BitReader`: Bit-level bitstream reader for Brotli bitstreams.
- `brotli.bit_writer`: Bit-level bitstream writer with accumulator packing.
- `brotli.huffman`: Huffman table definitions and canonical tree decoding.

## Version Accessors

```zig
pub const version = "0.0.4";
pub const version_number: u32 = 4;
pub const spec_version = "1.2.0";
pub const spec_version_number: u32 = 10200;

pub fn versionString() []const u8 // Returns "0.0.4"
pub fn versionNumber() u32        // Returns 4
```

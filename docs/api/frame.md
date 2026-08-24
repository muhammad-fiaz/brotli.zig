---
title: Format Introspection & Constants
description: Version accessors, limits, and format constants exposed by brotli.zig.
---

# Format Introspection & Constants

Brotli streams carry no per-frame header metadata like other formats; introspection is
limited to version info, bounds and format constants â€” all available without
touching compressed data.

## Version

```zig
pub const version = "0.0.3";
pub const version_number: u32 = 3;      // 0*100*100 + 0*100 + 2
pub const spec_version = "1.2.0";       // implemented RFC 7932 spec level
pub const spec_version_number: u32 = 10200;

pub fn versionString() []const u8
pub fn versionNumber() u32
```

## Bounds

```zig
/// Upper bound on compressed size (mirrors BrotliEncoderMaxCompressedSize).
pub fn maxCompressedSize(input_size: usize) usize // 2 for empty input

/// Decompress into a caller-provided buffer; returns bytes written.
pub fn decompressInto(allocator, input: []const u8, output: []u8) !usize
```

`decompressInto` doubles as size validation: allocate `maxCompressedSize(n)`
or a known expected size and catch `error.BrotliDecompressionError` /
`error.OutputTooSmall`.

## Constants (re-exported)

| Constant | Meaning |
|----------|---------|
| `BLOCKSIZE_MAX` | Maximum metablock length (16 MiB) |
| `MAX_QUALITY` / `MIN_QUALITY` / `DEFAULT_QUALITY` | 11 / 0 / 11 |
| `DEFAULT_WINDOW` / `MIN_WINDOW_BITS` / `MAX_WINDOW_BITS` | 22 / 10 / 24 |
| `LARGE_MAX_WINDOW_BITS` | 30 |
| `NUM_LITERAL_SYMBOLS` | 256 |
| `NUM_COMMAND_SYMBOLS` | 704 |
| `NUM_DISTANCE_SHORT_CODES` | 16 |
| `CONTEXT_MAP_MAX_RLE` | 16 |
| `MAX_NUMBER_OF_BLOCK_TYPES` | 256 |
| `WINDOW_GAP` | 16 |

## Detailed Error Reporting

```zig
var dec = brotli.Decoder.init(allocator, .{});
defer dec.deinit();
// ... feed input ...
if (dec.hasError()) {
    std.debug.print("decoder failed: {s}\n", .{dec.errorCode().name()});
}
```

Every `ErrorCode` has a stable `.name()` string mirroring the C
`BrotliDecoderErrorStr` values.

## Distance Parameters

```zig
pub const MAX_NPOSTFIX: u32 = 3;
pub const MAX_NDIRECT: u32 = 120;
pub fn distanceAlphabetSize(npostfix: u32, ndirect: u32, max_nbits: u32) u32
```

## Large Window

```zig
pub const LARGE_MIN_WBITS: u32 = 10;
pub const LARGE_MAX_WBITS: u32 = 30;
pub const LARGE_MAX_DISTANCE_BITS: u32 = 62;
pub const MAX_ALLOWED_DISTANCE: u32 = 0x7FFFFFFC;
```

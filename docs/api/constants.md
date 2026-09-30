---
title: Constants
description: Format constants, limits, and version metadata in brotli.zig.
---

# Constants

All format constants defined by RFC 7932 reside in `src/common/constants.zig` and are re-exported by `src/brotli.zig`.

## Top-Level Constants & Limits

`src/brotli.zig` exposes both canonical camelCase constants and traditional uppercase aliases:

| CamelCase Constant | Uppercase Alias | Value | Description |
|---|---|---|---|
| `maxBlockSize` | `BLOCKSIZE_MAX` | `1 << 24` (16 MiB) | Maximum uncompressed length of a single meta-block |
| `minQuality` | `MIN_QUALITY` | `0` | Minimum compression quality level |
| `maxQuality` | `MAX_QUALITY` | `11` | Maximum compression quality level |
| `defaultQuality` | `DEFAULT_QUALITY` | `11` | Default encoder quality level |
| `defaultWindow` | `DEFAULT_WINDOW` | `22` | Default window bits (`4 MiB - 16 bytes`) |
| `minWindowBits` | `MIN_WINDOW_BITS` | `10` | Minimum sliding window bits (`1 KiB`) |
| `maxWindowBits` | `MAX_WINDOW_BITS` | `24` | Maximum RFC 7932 standard window bits (`16 MiB`) |
| `largeMaxWindowBits` | `LARGE_MAX_WINDOW_BITS` | `30` | Maximum Large Window Brotli window bits (`1 GiB`) |
| `WINDOW_GAP` | `WINDOW_GAP` | `16` | Ring-buffer backward distance offset (RFC 7932 §9.1) |

## Format Alphabet Limits (`src/common/constants.zig`)

| Constant | Value | Description |
|---|---|---|
| `CONTEXT_MAP_MAX_RLE` | 16 | Maximum run-length code in context map header |
| `MAX_NUMBER_OF_BLOCK_TYPES` | 256 | Maximum number of block types per block category |
| `NUM_LITERAL_SYMBOLS` | 256 | Number of literal alphabet symbols |
| `NUM_COMMAND_SYMBOLS` | 704 | Number of insert-and-copy command alphabet symbols |
| `NUM_BLOCK_LEN_SYMBOLS` | 26 | Number of block-count prefix code symbols |
| `NUM_DISTANCE_SHORT_CODES` | 16 | Distance ring-buffer history codes |
| `REPEAT_PREVIOUS_CODE_LENGTH` | 16 | Code-length repeat marker symbol |
| `REPEAT_ZERO_CODE_LENGTH` | 17 | Zero-run repeat marker symbol |
| `CODE_LENGTH_CODES` | 18 | Code-length alphabet size |
| `MAX_NPOSTFIX` | 3 | Maximum distance postfix bits |
| `MAX_NDIRECT` | 120 | Maximum direct distance codes |
| `MAX_DISTANCE_BITS` | 24 | Maximum distance bits for standard streams |
| `MAX_DISTANCE` | `0x3FFFFFC` | Maximum addressable distance for standard streams |
| `LARGE_MAX_DISTANCE_BITS` | 62 | Maximum distance bits for Large Window Brotli |
| `MAX_ALLOWED_DISTANCE` | `0x7FFFFFFC` | Absolute upper bound on decoder distance lookback |

## Library Version Identifiers

```zig
pub const version = "0.0.4";
pub const version_number: u32 = 4;
pub const versionNumberValue: u32 = 4;

pub const spec_version = "1.2.0";
pub const spec_version_number: u32 = 10200;
pub const specVersion = "1.2.0";
pub const specVersionNumber: u32 = 10200;

pub fn versionString() []const u8 { return version; }
pub fn versionNumber() u32 { return version_number; }
```

## Example Usage

```zig
const brotli = @import("brotli");

std.debug.print("brotli.zig version: {s} (spec RFC 7932 v{s})\n", .{
    brotli.versionString(),
    brotli.specVersion,
});

const max_bound = brotli.maxCompressedSize(1024);
std.debug.print("Max compressed bound for 1024 bytes: {d}\n", .{max_bound});
```

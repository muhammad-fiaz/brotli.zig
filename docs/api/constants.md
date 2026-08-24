---
title: Constants
description: Format constants, limits, and version info exposed by brotli.zig.
---

# Constants

All format constants live in `src/common/constants.zig` and are re-exported
as top-level aliases in `src/brotli.zig`.

## Top-Level Aliases

```zig
pub const BLOCKSIZE_MAX = constants.BLOCK_SIZE_CAP; // 16 MiB metablock cap
pub const MAX_QUALITY = 11;
pub const MIN_QUALITY = 0;
pub const DEFAULT_QUALITY = 11;
pub const DEFAULT_WINDOW = 22;
pub const MIN_WINDOW_BITS = 10;  // large-window minimum
pub const MAX_WINDOW_BITS = 24;  // standard RFC 7932 maximum
pub const LARGE_MAX_WINDOW_BITS = 30;

pub const CONTEXT_MAP_MAX_RLE = 16;
pub const MAX_NUMBER_OF_BLOCK_TYPES = 256;
pub const NUM_LITERAL_SYMBOLS = 256;
pub const NUM_COMMAND_SYMBOLS = 704;
pub const NUM_DISTANCE_SHORT_CODES = 16;
pub const WINDOW_GAP = 16;
```

## Format Limits (`src/common/constants.zig`)

| Constant | Value | Description |
|----------|-------|-------------|
| `CONTEXT_MAP_MAX_RLE` | 16 | Max context-map run-length code |
| `MAX_NUMBER_OF_BLOCK_TYPES` | 256 | Block types per category |
| `NUM_LITERAL_SYMBOLS` | 256 | Literal alphabet size |
| `NUM_COMMAND_SYMBOLS` | 704 | Insert-and-copy alphabet size |
| `NUM_BLOCK_LEN_SYMBOLS` | 26 | Block-count prefix-code symbols |
| `REPEAT_PREVIOUS_CODE_LENGTH` | 16 | Code-length repeat marker |
| `REPEAT_ZERO_CODE_LENGTH` | 17 | Zero-run marker |
| `CODE_LENGTH_CODES` | 18 | Code-length alphabet size |
| `LARGE_MIN_WBITS` / `LARGE_MAX_WBITS` | 10 / 30 | Large-window LGWIN bounds |
| `NUM_DISTANCE_SHORT_CODES` | 16 | Distance ring-buffer codes |
| `MAX_NPOSTFIX` / `MAX_NDIRECT` | 3 / 120 | Distance parameterization bounds |
| `MAX_DISTANCE_BITS` | 24 | Standard window distance bits |
| `MAX_DISTANCE` | `0x3FFFFFC` | Max expressible distance (NPOSTFIX=0) |
| `MAX_ALLOWED_DISTANCE` | `0x7FFFFFFC` | Absolute decoder limit |
| `WINDOW_GAP` | 16 | Ring-buffer slack (spec Â§9.1) |
| `BLOCK_SIZE_CAP` | `1 << 24` | Metablock length ceiling |

## Version

```zig
pub const version = "0.0.4";
pub const version_number: u32 = 2;
pub const spec_version = "1.2.0";       // implemented format spec level
pub const spec_version_number: u32 = 10200;

pub fn versionString() []const u8 // "0.0.4"
pub fn versionNumber() u32        // 2
```

## Usage

```zig
const brotli = @import("brotli");

const bound = brotli.maxCompressedSize(data.len);
std.debug.print("quality {d}..{d}, window {d}..{d}\n", .{
    brotli.MIN_QUALITY, brotli.MAX_QUALITY,
    brotli.MIN_WINDOW_BITS, brotli.MAX_WINDOW_BITS,
});
```

---
title: CompressionOptions
description: Comprehensive configuration options for the native Brotli encoder.
---

# CompressionOptions

`CompressionOptions` configures the behavior, trade-offs, and features of the Brotli encoder. It is used with `brotli.compressWithOptions()`, `Compressor.init()`, and `StreamingCompressor.init()`.

Defined in `src/compress/encode.zig` and re-exported as `brotli.CompressionOptions` (and `brotli.EncoderOptions`).

## Struct Definition

```zig
pub const CompressionOptions = struct {
    quality: u32 = 11,
    lgWin: u32 = 22,
    mode: Mode = .generic,
    lgBlock: u32 = 0,
    disableLiteralContextModeling: bool = false,
    sizeHint: usize = 0,
    largeWindow: bool = false,
    nPostfix: u32 = 0,
    nDirect: u32 = 0,
    customDictionary: ?[]const u8 = null,
    progress: ?ProgressCallback = null,
    progressCtx: ?*anyopaque = null,
};
```

## Field Reference

| Field | Type | Default | Description |
|---|---|---|---|
| `quality` | `u32` | `11` | Compression level from `0` (fastest) to `11` (maximum compression ratio). |
| `lgWin` | `u32` | `22` | Base-2 logarithm of the sliding window size (`10..24`, or up to `30` if `largeWindow = true`). Max backward reference distance is `(1 << lgWin) - 16`. |
| `mode` | `Mode` | `.generic` | Text-analysis tune: `.generic`, `.text`, or `.font`. |
| `lgBlock` | `u32` | `0` | Base-2 logarithm of the input block size (`16..24`, or `0` for default). |
| `disableLiteralContextModeling` | `bool` | `false` | When `true`, disables second-order literal context modeling for faster encoding. |
| `sizeHint` | `usize` | `0` | Estimated uncompressed size; allows the encoder to tune block sizes and progress counters. |
| `largeWindow` | `bool` | `false` | Enables Large Window Brotli extension (RFC 7932 section 9.1 large window mode up to LGWIN 30). |
| `nPostfix` | `u32` | `0` | Number of postfix bits for distance coding (`0..3`). Clamped to `constants.MAX_NPOSTFIX`. |
| `nDirect` | `u32` | `0` | Number of direct distance codes (`0..120`). Clamped to `15 << nPostfix`. |
| `customDictionary` | `?[]const u8` | `null` | Pre-attached raw dictionary for small-payload compression. |
| `progress` | `?ProgressCallback` | `null` | Optional callback invoked as chunks are compressed. |
| `progressCtx` | `?*anyopaque` | `null` | User-defined context pointer passed to `progress`. |

## Compression Modes (`Mode`)

```zig
pub const Mode = enum(u3) {
    generic = 0,
    text = 1,
    font = 2,
};
```

- `.generic`: Default tuning suitable for general binary data.
- `.text`: Tunes literal context modeling heuristics for UTF-8 and ASCII text, source code, and JSON.
- `.font`: Tunes entropy coding for WOFF 2.0 font data.

## Progress Callback Signature

```zig
pub const ProgressCallback = *const fn (
    ctx: ?*anyopaque,
    bytes_done: usize,
    bytes_total: usize,
) void;
```

### Usage Example

```zig
const State = struct { done: usize = 0 };

fn onProgress(ctx: ?*anyopaque, bytes_done: usize, bytes_total: usize) void {
    const s: *State = @ptrCast(@alignCast(ctx.?));
    s.done = bytes_done;
    _ = bytes_total;
}

var state = State{};
const options = brotli.CompressionOptions{
    .quality = 9,
    .lgWin = 22,
    .mode = .text,
    .sizeHint = 1048576,
    .progress = onProgress,
    .progressCtx = &state,
};

const compressed = try brotli.compressWithOptions(allocator, my_data, options);
defer allocator.free(compressed);
```

## Parameter Identifiers (`setParameter`)

When using `Compressor.setParameter()`, configure options dynamically using camelCase constants or uppercase aliases:

| Identifier | Uppercase Alias | Value | Controls |
|---|---|---|---|
| `brotli.paramMode` | `PARAM_MODE` | 0 | `mode` |
| `brotli.paramQuality` | `PARAM_QUALITY` | 1 | `quality` |
| `brotli.paramLgWin` | `PARAM_LGWIN` | 2 | `lgWin` |
| `brotli.paramLgBlock` | `PARAM_LGBLOCK` | 3 | `lgBlock` |
| `brotli.paramDisableLiteralContextModeling` | `PARAM_DISABLE_LITERAL_CONTEXT_MODELING` | 4 | `disableLiteralContextModeling` |
| `brotli.paramSizeHint` | `PARAM_SIZE_HINT` | 5 | `sizeHint` |
| `brotli.paramLargeWindow` | `PARAM_LARGE_WINDOW` | 6 | `largeWindow` |
| `brotli.paramNPostfix` | `PARAM_NPOSTFIX` | 7 | `nPostfix` |
| `brotli.paramNDirect` | `PARAM_NDIRECT` | 8 | `nDirect` |

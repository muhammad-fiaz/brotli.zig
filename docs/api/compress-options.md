---
title: CompressionOptions
description: Options struct for brotli.compressWithOptions().
---

# CompressionOptions

Options for `brotli.compressWithOptions`, `Encoder` and
`StreamingCompressor`. Defined in `src/compress/encode.zig` and re-exported
as `brotli.CompressionOptions`.

## Definition

```zig
pub const Options = struct {
    quality: u32 = 11,
    lgwin: u32 = 22,
    mode: Mode = .generic,
    lgblock: u32 = 0,
    disable_literal_context_modeling: bool = false,
    size_hint: usize = 0,
    large_window: bool = false,
    npostfix: u32 = 0,
    ndirect: u32 = 0,
    progress: ?ProgressCallback = null,
    progress_ctx: ?*anyopaque = null,
};
```

## Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `quality` | `u32` | `11` | Quality level `0`..`11`; higher = better ratio, slower |
| `lgwin` | `u32` | `22` | Window bits `10`..`24` (clamped); bounds match distance |
| `mode` | `Mode` | `.generic` | `.generic`, `.text`, or `.font` analysis hint |
| `lgblock` | `u32` | `0` | Block-size hint (accepted for API parity) |
| `disable_literal_context_modeling` | `bool` | `false` | Accepted for API parity; encoder uses a fixed context layout |
| `size_hint` | `usize` | `0` | Expected total input size; improves progress reporting |
| `large_window` | `bool` | `false` | Accept LGWIN values up to 30 for interoperability |
| `npostfix` / `ndirect` | `u32` | `0` | Distance parameterization (accepted for API parity) |
| `progress` | `?ProgressCallback` | `null` | Called with `(ctx, bytes_done, bytes_total)` during streaming |
| `progress_ctx` | `?*anyopaque` | `null` | User pointer passed to the callback |

## Usage

```zig
const compressed = try brotli.compressWithOptions(allocator, data, .{
    .quality = 9,
    .lgwin = 22,
    .mode = .text,
    .size_hint = data.len,
});
```

## Progress Callbacks

```zig
const Ctx = struct { total: usize = 0 };
fn onProgress(ctx: ?*anyopaque, done: usize, total: usize) void {
    const c: *Ctx = @ptrCast(@alignCast(ctx.?));
    c.total = done;
}

var opts = brotli.CompressionOptions{ .quality = 9, .size_hint = file_size };
opts.progress = onProgress;
opts.progress_ctx = &ctx;
```

## Parameter Identifiers

For `Encoder.setParameter(id, value)` — mirrors the C enumeration:

| Constant | Value | Controls |
|----------|-------|----------|
| `PARAM_MODE` | 0 | mode |
| `PARAM_QUALITY` | 1 | quality |
| `PARAM_LGWIN` | 2 | lgwin |
| `PARAM_LGBLOCK` | 3 | lgblock |
| `PARAM_DISABLE_LITERAL_CONTEXT_MODELING` | 4 | context modeling flag |
| `PARAM_SIZE_HINT` | 5 | size_hint |
| `PARAM_LARGE_WINDOW` | 6 | large_window |
| `PARAM_NPOSTFIX` | 7 | npostfix |
| `PARAM_NDIRECT` | 8 | ndirect |

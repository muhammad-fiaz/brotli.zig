---
title: Compressor / Encoder
description: Reusable stateful compressor context with parameter control, dictionary attachment, and streaming operations.
---

# Compressor / Encoder

`Compressor` (also exported as `Encoder` and `brotli.Compressor`) represents a reusable Brotli compression context. Create once, use across multiple compression cycles via `reset()`, feed uncompressed data with `compressStream`, or compress memory slices directly.

Defined in `src/compress/encode.zig` and re-exported by `src/brotli.zig`.

## Struct Definition & Initialization

```zig
pub fn init(allocator: std.mem.Allocator, options: CompressionOptions) Compressor
pub fn deinit(self: *Compressor) void
```

### Example

```zig
const brotli = @import("brotli");

var comp = brotli.Compressor.init(allocator, .{
    .quality = 9,
    .lgWin = 22,
    .mode = .text,
});
defer comp.deinit();
```

## Reusable Context (`reset`)

To avoid repeated heap allocation when compressing many payloads, reset the context instead of destroying and recreating it:

```zig
pub fn reset(self: *Compressor, options: ?CompressionOptions) void
```

Passing `null` retains the existing options; passing a new `CompressionOptions` updates the configuration while retaining internal buffer capacity.

```zig
for (files) |file_data| {
    comp.reset(null);
    const compressed = try comp.compress(file_data);
    defer allocator.free(compressed);
    // Process compressed output...
}
```

## Direct Memory Compression

```zig
pub fn compress(self: *Compressor, input: []const u8) ![]u8
```

Compresses an input slice directly using the context's current settings and memory workspaces, returning a newly allocated output slice.

## Parameter Control

You can dynamically adjust compression parameters on an active context:

```zig
pub fn setParameter(self: *Compressor, id: u32, value: u32) bool
```

Accepts camelCase parameters or their uppercase aliases:

| Parameter Constant | Uppercase Alias | Value | Description |
|---|---|---|---|
| `brotli.paramMode` | `PARAM_MODE` | 0 | Compression mode (`0 = generic`, `1 = text`, `2 = font`) |
| `brotli.paramQuality` | `PARAM_QUALITY` | 1 | Quality level (`0..11`) |
| `brotli.paramLgWin` | `PARAM_LGWIN` | 2 | Window bits (`10..24`, up to `30` if large window) |
| `brotli.paramLgBlock` | `PARAM_LGBLOCK` | 3 | Block size bits hint |
| `brotli.paramDisableLiteralContextModeling` | `PARAM_DISABLE_LITERAL_CONTEXT_MODELING` | 4 | Skip second-order context modeling (`0` or `1`) |
| `brotli.paramSizeHint` | `PARAM_SIZE_HINT` | 5 | Estimated uncompressed stream size |
| `brotli.paramLargeWindow` | `PARAM_LARGE_WINDOW` | 6 | Enable Large Window Brotli (`0` or `1`) |
| `brotli.paramNPostfix` | `PARAM_NPOSTFIX` | 7 | Number of postfix bits for distance coding (`0..3`) |
| `brotli.paramNDirect` | `PARAM_NDIRECT` | 8 | Number of direct distance codes |

```zig
_ = comp.setParameter(brotli.paramQuality, 6);
_ = comp.setParameter(brotli.paramLgWin, 20);
_ = comp.setParameter(brotli.paramSizeHint, 8192);
```

## Progress Callback

```zig
pub fn setProgress(self: *Compressor, cb: ?ProgressCallback, ctx: ?*anyopaque) void
```

Registers an optional progress observer that fires periodically during compression of large inputs:

```zig
const Context = struct { total_done: usize = 0 };

fn onProgress(ctx: ?*anyopaque, done: usize, total: usize) void {
    const state: *Context = @ptrCast(@alignCast(ctx.?));
    state.total_done = done;
    _ = total;
}

var ctx = Context{};
comp.setProgress(onProgress, &ctx);
```

## Custom Dictionary Attachment

```zig
pub fn attachDictionary(self: *Compressor, data: []const u8) bool
```

Attaches raw dictionary bytes to be used as history before the start of the uncompressed stream. Must be called before any data is fed to `compressStream` or `compress`. The dictionary slice is referenced (not copied) and must remain valid for the duration of the compression.

## Low-Level Streaming Operations

```zig
pub fn compressStream(self: *Compressor, op: Operation, input: ?[]const u8) !void
```

The `op` parameter controls the state transition:

| Operation | Behavior |
|---|---|
| `.process` | Buffer and compress incoming input; emit complete meta-blocks |
| `.flush` | Force all buffered data into completed (non-final) blocks |
| `.finish` | Flush all remaining data and emit the final empty or terminal block |
| `.emit_metadata` | Write the input as an uncompressed RFC 7932 section 9.2 metadata block |

### Draining Output

```zig
pub fn hasMoreOutput(self: *const Compressor) bool
pub fn takeOutput(self: *Compressor, dst: []u8) usize
pub fn isFinished(self: *const Compressor) bool
```

### Streaming Loop Example

```zig
var comp = brotli.Compressor.init(allocator, .{ .quality = 9 });
defer comp.deinit();

// 1. Process chunks
try comp.compressStream(.process, chunk1);
try comp.compressStream(.process, chunk2);

// 2. Finish stream
try comp.compressStream(.finish, null);

// 3. Drain output into buffer
var out_buf: [4096]u8 = undefined;
while (comp.hasMoreOutput()) {
    const n = comp.takeOutput(&out_buf);
    // Write out_buf[0..n] to destination...
}
```

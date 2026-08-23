---
title: Encoder
description: Reusable streaming encoder with full parameter control.
---

# Encoder

A reusable encoder context. Create once, feed data with
`compressStream`, take compressed bytes as they appear. Defined in
`src/compress/encode.zig` and re-exported as `brotli.Encoder`.

For the simpler chunk facade see [StreamCompressor](./stream-compressor).

## Creation

```zig
pub fn init(allocator: std.mem.Allocator, options: CompressionOptions) Encoder
```

```zig
var enc = brotli.Encoder.init(allocator, .{ .quality = 9 });
defer enc.deinit();
```

## Parameter Control

```zig
pub fn setParameter(self: *Encoder, id: u32, value: u32) bool
```

Accepts the `PARAM_*` identifiers (mirroring the C enumeration):

```zig
try testing.expect(enc.setParameter(brotli.PARAM_QUALITY, 9));
try testing.expect(enc.setParameter(brotli.PARAM_LGWIN, 20));
try testing.expect(enc.setParameter(brotli.PARAM_SIZE_HINT, 4096));
try testing.expect(!enc.setParameter(999, 1)); // unknown -> false
```

## Progress Callbacks

```zig
pub fn setProgress(self: *Encoder, cb: ?ProgressCallback, ctx: ?*anyopaque) void
```

The callback fires during streaming compression of large inputs:

```zig
const Ctx = struct { last_done: usize = 0 };
fn onProgress(ctx: ?*anyopaque, done: usize, total: usize) void {
    const c: *Ctx = @ptrCast(@alignCast(ctx.?));
    c.last_done = done;
}
enc.setProgress(onProgress, &ctx);
```

## Custom Dictionary

```zig
pub fn attachDictionary(self: *Encoder, data: []const u8) bool
```

Must precede the first `compressStream`. Data is referenced (not copied).
Decoders must attach the identical bytes to resolve the produced
back-references.

## Streaming

```zig
pub fn compressStream(self: *Encoder, op: Operation, input: ?[]const u8) !void
```

`Operation` mirrors the C enumeration:

| Operation | Behavior |
|-----------|----------|
| `.process` | Compress buffered input; emit complete blocks |
| `.flush` | Force all pending input into finished (non-final) blocks |
| `.finish` | Flush everything and emit the final block; marks the stream done |

Output accumulates internally; drain it via:

```zig
pub fn hasMoreOutput(self: *const Encoder) bool
pub fn takeOutput(self: *Encoder, dst: []u8) usize // returns bytes copied
```

## Completion

```zig
pub fn isFinished(self: *const Encoder) bool
```

## Example

```zig
var enc = brotli.Encoder.init(allocator, .{ .quality = 11 });
defer enc.deinit();

try enc.compressStream(.process, chunk_a);
try enc.compressStream(.flush, null);
try enc.compressStream(.process, chunk_b);
try enc.compressStream(.finish, null);

// Collect all output.
var out = std.ArrayList(u8).empty;
defer out.deinit(allocator);
try out.appendSlice(allocator, enc.out.items[enc.out_pos..]);
```

---
title: StreamingDecompressor
description: Chunk-based streaming decompression facade.
---

# StreamingDecompressor

Chunk-based decompression facade over `Decoder`. Defined in
`src/brotli.zig`, re-exported as `brotli.StreamingDecompressor`.

## Creation

```zig
pub fn init(allocator: std.mem.Allocator, options: DecoderOptions) StreamingDecompressor
```

```zig
var sd = brotli.StreamingDecompressor.init(allocator, .{});
defer sd.deinit();
```

## Feeding & Draining

```zig
pub fn feed(self: *StreamingDecompressor, chunk: []const u8) void
pub fn take(self: *StreamingDecompressor, out: []u8) !usize // bytes written
pub fn isFinished(self: *const StreamingDecompressor) bool
```

```zig
var out_buf: [4096]u8 = undefined;
for (chunks) |chunk| {
    sd.feed(chunk);
    const n = try sd.take(&out_buf);
    // consume out_buf[0..n]
}
sd.feed(&.{});
while (!sd.isFinished()) _ = try sd.take(&out_buf);
```

## Diagnostics

```zig
pub fn hasError(self: *const StreamingDecompressor) bool
pub fn errorCode(self: *const StreamingDecompressor) ErrorCode
pub fn totalOut(self: *const StreamingDecompressor) u64
```

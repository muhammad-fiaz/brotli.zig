---
title: StreamingCompressor
description: Chunk-based streaming compression facade.
---

# StreamingCompressor

Chunk-based compression facade over `Encoder`. Feed input chunks with
`process`, drain compressed bytes from the returned slices, then `finish`.
Defined in `src/compress/encode.zig`, re-exported as
`brotli.StreamingCompressor`.

## Creation

```zig
pub fn init(allocator: std.mem.Allocator, options: CompressionOptions) StreamingCompressor
```

```zig
var sc = brotli.StreamingCompressor.init(allocator, .{ .quality = 9 });
defer sc.deinit();
```

## Feeding Input

```zig
pub fn process(self: *StreamingCompressor, chunk: []const u8) ![]u8
```

Returns freshly allocated compressed bytes (caller frees). Empty slice when
the encoder has not yet produced output.

## Flush / Finish

```zig
pub fn flush(self: *StreamingCompressor) ![]u8   // force all pending blocks
pub fn finish(self: *StreamingCompressor) ![]u8  // emit final block; stream done
pub fn isFinished(self: *const StreamingCompressor) bool
```

## Extras

```zig
pub fn setProgress(self: *StreamingCompressor, cb: ?ProgressCallback, ctx: ?*anyopaque) void
pub fn attachDictionary(self: *StreamingCompressor, data: []const u8) bool
```

## Example

```zig
var sc = brotli.StreamingCompressor.init(allocator, .{ .quality = 11 });
defer sc.deinit();

var out = std.ArrayList(u8).empty;
defer out.deinit(allocator);

for (chunks) |chunk| {
    const piece = try sc.process(chunk);
    defer allocator.free(piece);
    try out.appendSlice(allocator, piece);
}
const tail = try sc.finish();
defer allocator.free(tail);
try out.appendSlice(allocator, tail);
```

## Metadata Emission

```zig
pub fn emitMetadata(self: *StreamingCompressor, payload: []const u8) ![]u8
```

Emits a metadata metablock carrying arbitrary bytes. Metadata blocks are
skipped by decoders that do not observe them and never appear in the
decompressed output.

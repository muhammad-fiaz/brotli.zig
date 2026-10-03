---
title: StreamingCompressor
description: Incremental streaming Brotli compressor supporting std.Io.Writer pipelines and chunked memory processing.
---

# StreamingCompressor

`StreamingCompressor` is an incremental compression facade built on top of the native Brotli encoder. It provides two ergonomic modes of operation:

1. **Direct I/O Streaming**: Push uncompressed chunks directly into any Zig 0.17 `std.Io.Writer` (`write()`, `flush()`, `finish()`).
2. **Chunked Memory Allocation**: Feed uncompressed slices and receive newly compressed allocated byte buffers (`process()`, `flushAlloc()`, `finishAlloc()`).

Defined in `src/streaming/compressor.zig` and re-exported by `src/brotli.zig`.

## Initialization & Lifecycle

```zig
pub fn init(allocator: std.mem.Allocator, options: CompressionOptions) StreamingCompressor
pub fn deinit(self: *StreamingCompressor) void
pub fn reset(self: *StreamingCompressor, options: CompressionOptions) void
```

### Example

```zig
const brotli = @import("brotli");

var stream_comp = brotli.StreamingCompressor.init(allocator, .{
    .quality = 9,
    .mode = .text,
});
defer stream_comp.deinit();
```

## Direct `std.Io.Writer` Streaming

Compress data incrementally directly to any standard Zig `std.Io.Writer` (e.g. file, network socket, or pipe):

```zig
pub fn write(self: *StreamingCompressor, chunk: []const u8, writer: *std.Io.Writer) !void
pub fn flush(self: *StreamingCompressor, writer: *std.Io.Writer) !void
pub fn finish(self: *StreamingCompressor, writer: *std.Io.Writer) !void
```

### Complete I/O Example

```zig
var file_out = try std.fs.cwd().createFile("output.br", .{});
defer file_out.close();

var file_writer = file_out.writer(&.{});
const writer = &file_writer.interface;

// Stream chunks
while (try getNextChunk()) |chunk| {
    try stream_comp.write(chunk, writer);
}

// Flush pending meta-blocks and emit the stream terminator
try stream_comp.finish(writer);
```

## Chunked Memory Buffer API

If you prefer receiving owned byte slices without an I/O writer:

```zig
pub fn process(self: *StreamingCompressor, chunk: []const u8) ![]u8
pub fn flushAlloc(self: *StreamingCompressor) ![]u8
pub fn finishAlloc(self: *StreamingCompressor) ![]u8
```

- Each call returns a newly allocated slice containing any compressed bytes emitted during that step.
- An empty slice (`len == 0`) means the encoder is still buffering input to form an optimal meta-block.
- The caller is responsible for freeing returned slices.

### Memory Chunk Example

```zig
var out = std.ArrayList(u8).empty;
defer out.deinit(allocator);

for (chunks) |chunk| {
    const compressed_slice = try stream_comp.process(chunk);
    defer allocator.free(compressed_slice);
    try out.appendSlice(allocator, compressed_slice);
}

const final_slice = try stream_comp.finishAlloc();
defer allocator.free(final_slice);
try out.appendSlice(allocator, final_slice);
```

## Metadata Blocks

RFC 7932 section 9.2 permits inserting uncompressed metadata blocks into the bitstream that are skipped by standard decoders:

```zig
pub fn emitMetadata(self: *StreamingCompressor, payload: []const u8, writer: *std.Io.Writer) !void
```

## Custom Dictionary & Progress

```zig
pub fn attachDictionary(self: *StreamingCompressor, data: []const u8) bool
pub fn setProgress(self: *StreamingCompressor, cb: ?ProgressCallback, ctx: ?*anyopaque) void
```

## State & Error Inspection

```zig
pub fn isFinished(self: *const StreamingCompressor) bool
pub fn hasError(self: *const StreamingCompressor) bool
pub fn lastError(self: *const StreamingCompressor) ?anyerror
```

---
title: StreamingDecompressor
description: Incremental streaming Brotli decompressor supporting std.Io pipelines and chunked memory feeding.
---

# StreamingDecompressor

`StreamingDecompressor` is an incremental decompression engine that decodes arbitrary chunks of compressed data. It supports:

1. **Direct `std.Io` Pipeline**: Decompress directly between any Zig 0.17 `std.Io.Reader` and `std.Io.Writer` via `read()`.
2. **Chunked Memory Feed/Take**: Arbitrary byte-boundary feeding (`feed()`, `endInput()`) and decoding into fixed buffers (`take()`).

Defined in `src/streaming/decompressor.zig` and re-exported by `src/brotli.zig`.

## Initialization & Lifecycle

```zig
pub fn init(allocator: std.mem.Allocator, options: DecompressionOptions) StreamingDecompressor
pub fn deinit(self: *StreamingDecompressor) void
pub fn reset(self: *StreamingDecompressor, options: DecompressionOptions) void
```

### Example

```zig
const brotli = @import("brotli");

var stream_dec = brotli.StreamingDecompressor.init(allocator, .{
    .largeWindow = true,
});
defer stream_dec.deinit();
```

## Direct `std.Io` Pipeline (`read`)

Decompress from a reader directly into a writer in a single streaming call:

```zig
pub fn read(
    self: *StreamingDecompressor,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
) !void
```

### Example

```zig
var file_in = try std.fs.cwd().openFile("compressed.br", .{});
defer file_in.close();

var file_out = try std.fs.cwd().createFile("decompressed.txt", .{});
defer file_out.close();

var in_reader = file_in.reader(&.{});
var out_writer = file_out.writer(&.{});

try stream_dec.read(&in_reader.interface, &out_writer.interface);
```

## Chunked Memory Feeding & Draining (`feed` / `take`)

When working with network packets or non-contiguous memory chunks:

```zig
pub fn feed(self: *StreamingDecompressor, chunk: []const u8) !void
pub fn endInput(self: *StreamingDecompressor) void
pub fn take(self: *StreamingDecompressor, out: []u8) !usize
```

- `feed(chunk)`: Appends compressed bytes to the decompressor's internal intake. Returns error if memory allocation fails.
- `take(out)`: Decodes available uncompressed data into `out`, returning the number of bytes written.
- `endInput()`: Notifies the decompressor that all input has been sent.

### Feed & Take Loop Example

```zig
var out_buf: [16384]u8 = undefined;

for (network_packets) |packet| {
    try stream_dec.feed(packet);

    while (true) {
        const n = try stream_dec.take(&out_buf);
        if (n == 0) break;
        // Process out_buf[0..n]...
    }
}

// Signal EOF
stream_dec.endInput();
while (!stream_dec.isFinished()) {
    const n = try stream_dec.take(&out_buf);
    if (n == 0) break;
    // Process final out_buf[0..n]...
}
```

## Dictionary Attachment

Attach custom raw or compound dictionaries before feeding any input:

```zig
pub fn attachDictionary(self: *StreamingDecompressor, data: []const u8) bool
pub fn attachSharedDictionary(self: *StreamingDecompressor, dict: *const SharedDictionary) bool
```

## Diagnostics & Inspection

```zig
pub fn isFinished(self: *const StreamingDecompressor) bool
pub fn hasError(self: *const StreamingDecompressor) bool
pub fn errorCode(self: *const StreamingDecompressor) ErrorCode
pub fn totalOut(self: *const StreamingDecompressor) u64
```

- `isFinished()`: Returns `true` once the entire Brotli stream has reached its terminating block.
- `errorCode()`: Returns the detailed `ErrorCode` enum value if an error occurs.
- `totalOut()`: Cumulative count of uncompressed bytes emitted so far.


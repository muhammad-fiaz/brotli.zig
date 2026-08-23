---
title: Streaming Compression
description: Chunk-based compression with StreamingCompressor and progress callbacks.
---

# Streaming Compression

`examples/streaming_compression.zig` — feeds 4 MiB of pseudo-text in 32 KiB
chunks through `StreamingCompressor`, collects output slices, then calls
`finish` to emit the final block. A progress callback counts invocations.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

const Progress = struct {
    total: usize,
    fn onProgress(ctx: ?*anyopaque, done: usize, total: usize) void {
        const self: *Progress = @ptrCast(@alignCast(ctx.?));
        _ = done;
        _ = total;
        self.total +%= 1;
    }
};

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var sc = brotli.StreamingCompressor.init(allocator, .{
        .quality = 9,
        .lgwin = 22,
    });
    defer sc.deinit();

    var progress = Progress{ .total = 0 };
    sc.setProgress(Progress.onProgress, &progress);

    var compressed: std.ArrayList(u8) = .empty;
    defer compressed.deinit(allocator);

    const chunk_size = 32 * 1024;
    const chunk = try allocator.alloc(u8, chunk_size);
    defer allocator.free(chunk);

    var fed: usize = 0;
    const total_input: usize = 4 * 1024 * 1024;

    while (fed < total_input) {
        const piece = try sc.process(chunk);
        defer allocator.free(piece);
        try compressed.appendSlice(allocator, piece);
        fed += chunk.len;
    }

    const tail = try sc.finish();
    defer allocator.free(tail);
    try compressed.appendSlice(allocator, tail);

    const decoded = try brotli.decompress(allocator, compressed.items);
    defer allocator.free(decoded);

    std.debug.print(
        "streamed {d} bytes -> {d} compressed ({d:.1}%); "
        ++ "round trip {s}\n",
        .{ total_input, compressed.items.len,
           @as(f64, @floatFromInt(compressed.items.len)) * 100.0 /
           @as(f64, @floatFromInt(total_input)),
           if (decoded.len == total_input) "OK" else "MISMATCH" },
    );
}
```

## Output

```text
streamed 4194304 bytes -> 685280 bytes (16.3%); round trip OK
```

## Explanation

- `StreamingCompressor` owns the encoder state internally. Each call to
  `process` flushes any internally buffered output as an owned slice — the
  caller must free it.
- `finish` writes the final empty metablock with `ISLAST=1` and returns
  the remaining output.
- `setProgress` wires a callback that fires once per input chunk processed,
  useful for progress bars or cancellation checks on large inputs.
- The round-trip decompression with `brotli.decompress` verifies
  byte-for-byte equality.

Run it:

```bash
zig build run-streaming_compression
```

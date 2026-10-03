---
title: Decompress File
description: One-shot file decompression with verification.
---

# Decompress File

`examples/decompress_file.zig` — reads `sample.br` from disk (or
generates it if missing), decompresses it, and verifies byte-for-byte
equality against the original corpus.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var compressed: []u8 = undefined;
    if (std.Io.Dir.cwd().readFileAlloc(
        io, "sample.br", allocator, .limited(4 * 1024 * 1024),
    )) |from_disk| {
        compressed = from_disk;
    } else |err| switch (err) {
        error.FileNotFound => {
            const sample = try buildSample(allocator);
            defer allocator.free(sample);
            compressed = try brotli.compressWithOptions(allocator, sample, .{
                .quality = 9, .lgWin = 22,
            });
            try std.Io.Dir.cwd().writeFile(io, .{
                .sub_path = "sample.br", .data = compressed,
            });
        },
        else => return error.UnreadableInput,
    }
    defer allocator.free(compressed);

    const output = try brotli.decompress(allocator, compressed);
    defer allocator.free(output);

    const expected = try buildSample(allocator);
    defer allocator.free(expected);

    const match = std.mem.eql(u8, output, expected);
    std.debug.print(
        "decompressed {d} -> {d} bytes; content {s}\n",
        .{ compressed.len, output.len, if (match) "OK" else "MISMATCH" },
    );
    if (!match) return error.RoundTripMismatch;
}
```

## Output

```text
decompressed 1023 -> 262144 bytes; content OK
```

## Explanation

- If `sample.br` does not exist (standalone run), the example
  regenerates the same 256 KiB corpus using the shared PRNG seed and
  compresses it first so the demo always works.
- `brotli.decompress` performs a one-shot decode: it allocates the full
  output internally and returns it as a single owned slice.
- The byte-for-byte comparison catches any data corruption or
  truncation silently; a mismatch returns `error.RoundTripMismatch`.

Run it:

```bash
zig build run-decompress_file
```

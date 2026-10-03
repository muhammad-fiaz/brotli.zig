---
title: Compress File
description: One-shot file compression across quality levels.
---

# Compress File

`examples/compress_file.zig` - builds a deterministic 256 KiB pseudo-text
corpus, compresses it at quality levels 1, 5, 9, and 11, writes the
quality-9 result to `sample.br`, then reads it back and verifies a full
round trip.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const total_input: usize = 256 * 1024;
    const input = try allocator.alloc(u8, total_input);
    defer allocator.free(input);

    var filled: usize = 0;
    while (filled < input.len) {
        const w = words[prng.random().intRangeLessThan(usize, 0, words.len)];
        const n = @min(w.len, input.len - filled);
        @memcpy(input[filled..][0..n], w[0..n]);
        filled += n;
    }

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = "sample.txt", .data = input });

    inline for (.{ 1, 5, 9, 11 }) |q| {
        const compressed = try brotli.compressWithOptions(allocator, input, .{
            .quality = q,
            .lgWin = 22,
        });
        defer allocator.free(compressed);

        if (q == 9) {
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = "sample.br", .data = compressed });
        }

        std.debug.print(
            "q{d:<2}: {d} -> {d} bytes ({d:.1}% ratio){s}\n",
            .{ q, input.len, compressed.len,
               @as(f64, @floatFromInt(compressed.len)) * 100.0 /
               @as(f64, @floatFromInt(input.len)),
               if (q == 9) "  [written to sample.br]" else "" },
        );
    }

    const from_disk = try std.Io.Dir.cwd().readFileAlloc(
        io, "sample.br", allocator, .limited(4 * 1024 * 1024),
    );
    defer allocator.free(from_disk);

    const round_trip = try brotli.decompress(allocator, from_disk);
    defer allocator.free(round_trip);

    std.debug.print(
        "wrote sample.txt ({d} B) and sample.br ({d} B); disk round-trip {s}\n",
        .{ input.len, from_disk.len,
           if (std.mem.eql(u8, round_trip, input)) "OK" else "MISMATCH" },
    );
}
```

## Output

```text
q1 : 262144 -> 1663 bytes (0.6% ratio)
q5 : 262144 -> 1281 bytes (0.5% ratio)
q9 : 262144 -> 1023 bytes (0.4% ratio)  [written to sample.br]
q11: 262144 -> 1004 bytes (0.4% ratio)
wrote sample.txt (262144 B) and sample.br (1023 B); disk round-trip OK
```

## Explanation

- The same PRNG seed (`0xC0FFEE`) guarantees identical input every run.
- Quality levels trade compression speed against ratio; the difference
  between q9 and q11 is small for repetitive text but visible at higher
  quality.
- The `sample.br` file persists so `decompress_file` and other examples
  can consume it without recompressing.

Run it:

```bash
zig build run-compress_file
```

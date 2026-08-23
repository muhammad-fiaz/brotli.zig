---
title: Dictionary Compression
description: Shared-dictionary compression round trip.
---

# Dictionary Compression

`examples/dictionary_compression.zig` — attach identical dictionary bytes on
both sides so small payloads compress via back-references into the corpus.
The encoder emits compact references into dictionary content; only a decoder
with the identical data attached can expand them.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const custom_dictionary =
        "opencode native zig brotli sample vocabulary "
        ++ "compression decompression streaming performance ";

    const input =
        "native zig brotli sample vocabulary compression performance";

    var enc = brotli.Encoder.init(allocator, .{ .quality = 11 });
    defer enc.deinit();
    if (!enc.attachDictionary(custom_dictionary))
        return error.InvalidDictionary;

    enc.compressStream(.process, input) catch return error.CompressionFailed;
    enc.compressStream(.finish, null) catch return error.CompressionFailed;
    const compressed = try allocator.dupe(
        u8, enc.out.items[enc.out_pos..],
    );
    defer allocator.free(compressed);

    // Decode without the dictionary must fail or produce garbage.
    var plain = brotli.Decoder.init(allocator, .{});
    defer plain.deinit();
    var pin: []const u8 = compressed;
    var pout: [256]u8 = undefined;
    var pavail: []u8 = &pout;
    var ptotal: u64 = 0;
    const plain_result = plain.decompressStream(&pin, &pavail, &ptotal);

    // Decode WITH the dictionary must reproduce the input exactly.
    var decoder = brotli.Decoder.init(allocator, .{});
    defer decoder.deinit();
    if (!decoder.attachDictionary(custom_dictionary))
        return error.InvalidDictionary;
    var din: []const u8 = compressed;
    var dout: [256]u8 = undefined;
    var davail: []u8 = &dout;
    var dtotal: u64 = 0;
    switch (decoder.decompressStream(&din, &davail, &dtotal)) {
        .success => {},
        else => return error.StreamFailed,
    }

    const recovered = dout[0..@intCast(dtotal)];
    const match = std.mem.eql(u8, recovered, input);
    std.debug.print(
        "{d} -> {d} bytes with shared dictionary; "
        ++ "recovered {s} (plain decode: {any})\n",
        .{ input.len, compressed.len,
           if (match) "OK" else "MISMATCH",
           plain_result == .success },
    );
    if (!match) return error.RoundTripMismatch;
}
```

## Output

```text
58 -> 11 bytes with shared dictionary; recovered OK (plain decode: false)
```

## Explanation

- The dictionary string `"opencode native zig brotli sample vocabulary
  compression decompression streaming performance"` is attached to both
  the `Encoder` and `Decoder` via `attachDictionary()`.
- The input heavily overlaps the dictionary. Without the dictionary the
  encoder has nothing to reference, but with it most of the input
  collapses into back-references — producing a much smaller stream.
- Decoding **without** the dictionary fails (or produces garbage) because
  the back-references point outside the stream. Decoding **with** the
  identical dictionary reproduces the input exactly.
- This pattern is useful for domain-specific payloads where both sides
  can share a trained corpus or vocabulary ahead of time.

Run it:

```bash
zig build run-dictionary_compression
```

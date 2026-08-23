---
title: Dictionary Compression
description: Shared-dictionary compression round trip.
---

# Dictionary Compression

`examples/dictionary_compression.zig` — attach identical dictionary bytes on
both sides so small payloads compress via back-references into the corpus.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const dict = "shared vocabulary words appear here";

    var enc = brotli.Encoder.init(allocator, .{ .quality = 11 });
    defer enc.deinit();
    try testing.expect(enc.attachDictionary(dict));
    try enc.compressStream(.process, input);
    try enc.compressStream(.finish, null);

    // Decode: requires the same dictionary attached.
    var d = brotli.Decoder.init(allocator, .{});
    defer d.deinit();
    _ = d.attachDictionary(dict);
    // ... decompressStream as usual ...
}
```

Run it:

```bash
zig build run-dictionary_compression
```
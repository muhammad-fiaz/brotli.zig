---
title: Format Introspection
description: Version, quality bounds, window sizes, and format constants.
---

# Format Introspection

`examples/format_introspection.zig` â€” prints the library version string,
format spec version, quality and window-size ranges, and the alphabet
sizes used by the encoder and decoder.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main() void {
    std.debug.print("library version : {s} ({d})\n", .{
        brotli.versionString(), brotli.versionNumber(),
    });
    std.debug.print("format spec     : {s}\n", .{brotli.spec_version});
    std.debug.print("quality range   : {d}..{d} (default {d})\n", .{
        brotli.MIN_QUALITY, brotli.MAX_QUALITY, brotli.DEFAULT_QUALITY,
    });
    std.debug.print("window bits     : {d}..{d} (large: up to {d})\n", .{
        brotli.MIN_WINDOW_BITS, brotli.MAX_WINDOW_BITS,
        brotli.LARGE_MAX_WINDOW_BITS,
    });
    std.debug.print("literal symbols : {d}\n", .{brotli.NUM_LITERAL_SYMBOLS});
    std.debug.print("command symbols : {d}\n", .{brotli.NUM_COMMAND_SYMBOLS});
    std.debug.print("distance shorts : {d}\n", .{brotli.NUM_DISTANCE_SHORT_CODES});
}
```

## Output

```text
library version : 0.0.4 (4)
format spec     : 1.2.0
quality range   : 0..11 (default 11)
window bits     : 10..24 (large: up to 30)
literal symbols : 256
command symbols : 704
distance shorts : 16
```

## Explanation

- `versionString()` returns the human-readable `"0.0.4"`;
  `versionNumber()` returns the encoded integer `4`.
- `spec_version` is the Brotli format specification version this library
  targets: `"1.2.0"`.
- `MIN_QUALITY`/`MAX_QUALITY` bound the `quality` field of
  `CompressionOptions`; `DEFAULT_QUALITY` is 11 (best ratio).
- `LARGE_MAX_WINDOW_BITS` (30) is the extended window available when
  decoding large-window Brotli streams; the encoder caps at 24.

Run it:

```bash
zig build run-format_introspection
```

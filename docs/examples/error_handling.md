---
title: Error Handling
description: Corruption, truncation, and detailed decoder diagnostics.
---

# Error Handling

`examples/error_handling.zig` - every failure surfaces as a typed Zig error,
and the streaming decoder records a precise `ErrorCode`.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main() void {
    // Truncated garbage cannot form a valid window header.
    const garbage = [_]u8{ 0x91, 0xff, 0xff, 0xff };

    const output = brotli.decompress(std.heap.page_allocator, &garbage) catch |e| {
        std.debug.print("expected failure: {s}\n", .{@errorName(e)});
        return;
    };
    defer std.heap.page_allocator.free(output);
}
```

## Detailed Decoder Diagnostics

The streaming decoder never panics on untrusted input. Any format violation
returns `.err` with a named code mirroring the C `BrotliDecoderErrorStr`
values:

```zig
var d = brotli.Decoder.init(allocator, .{});
defer d.deinit();

const r = d.decompressStream(&in, &avail, &total);
if (r == .err) {
    std.debug.print("failed: {s}\n", .{d.errorCode().name()});
    // e.g. "ERROR_FORMAT_WINDOW_BITS", "ERROR_FORMAT_PADDING_1", ...
}
```

## Error Categories

| Error | Cause |
|-------|-------|
| `error.BrotliDecompressionError` | One-shot decode of corrupt data |
| `error.NeedsMoreInput` | Stream ended mid-decode |
| `error.OutputTooSmall` | `decompressInto` target too small |
| `error.BrotliCompressionError` | Encoder failure (allocation) |
| `error.OutOfMemory` | Propagated from any allocation |

Run it:

```bash
zig build run-error_handling
```

---
title: Errors
description: Error handling and detailed decoder diagnostics.
---

# Errors

## Top-level errors

One-shot functions return Zig errors:

| Error | Cause |
|-------|-------|
| `error.BrotliDecompressionError` | Corrupt/truncated stream |
| `error.NeedsMoreInput` | Stream ended mid-decode |
| `error.OutputTooSmall` | `decompressInto` target too small |
| `error.BrotliCompressionError` | Encoder failure (allocation) |

## Detailed Decoder Diagnostics

The streaming decoder records a precise `ErrorCode` mirroring the C
`BrotliDecoderErrorCode` enumeration:

```zig
var d = brotli.Decoder.init(allocator, .{});
defer d.deinit();

const r = d.decompressStream(&in, &avail, &total);
if (r == .err) {
    std.debug.print("failed: {s} (code {d})\n", .{ d.errorCode().name(), @intFromEnum(d.errorCode()) });
}
```

`ErrorCode.name()` returns the exact C strings (`"ERROR_FORMAT_CL_SPACE"`,
`"ERROR_FORMAT_PADDING_1"`, …). `isError()` distinguishes real failures from
the non-error sentinels.

## Result Codes

`DecodeResult`: `.success`, `.needs_more_input`, `.needs_more_output`,
`.err` — mirroring `BrotliDecoderResult`.

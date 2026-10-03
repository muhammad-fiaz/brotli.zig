---
title: Decompression
description: Decompressing data with brotli.zig.
---

# Decompression

## One-Shot

```zig
const out = try brotli.decompress(allocator, compressed);
defer allocator.free(out);
```

## Into a Preallocated Buffer

```zig
var dst: [1024]u8 = undefined;
const n = try brotli.decompressInto(allocator, compressed, &dst);
// dst[0..n] holds the decompressed bytes
```

## Streaming

```zig
var sd = brotli.StreamingDecompressor.init(allocator, .{});
defer sd.deinit();

var out_buf: [4096]u8 = undefined;
for (chunks) |chunk| {
    sd.feed(chunk);
    const n = try sd.take(&out_buf);
    // consume out_buf[0..n]
}
sd.feed(&.{});
while (!sd.isFinished()) _ = try sd.take(&out_buf);
```

## Raw Decoder

For exact control over input/output windows use `Decoder.decompressStream`
directly - see [Decoder](../api/decompressor).

## Errors

Corrupt or truncated streams return `error.BrotliDecompressionError`; the
underlying decoder exposes precise `ErrorCode` values via `errorCode()`.
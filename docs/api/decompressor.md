---
title: Decompressor / Decoder
description: Reusable stateful decoder context with streaming, buffer reuse, dictionary attachment, and detailed error inspection.
---

# Decompressor / Decoder

`Decompressor` (also exported as `Decoder`, `DecompressionContext`, and `brotli.Decompressor`) represents a stateful Brotli decompression engine. It supports incremental stream decoding across arbitrary buffer boundaries, full state resets for zero-allocation reuse, and rich error inspection.

Defined in `src/decompress/decode.zig` and re-exported by `src/brotli.zig`.

## Struct Definition & Initialization

```zig
pub fn init(allocator: std.mem.Allocator, options: DecompressionOptions) Decompressor
pub fn deinit(self: *Decompressor) void
```

### Example

```zig
const brotli = @import("brotli");

var dec = brotli.Decompressor.init(allocator, .{
    .largeWindow = true,
    .maxOutputSize = 64 * 1024 * 1024, // 64 MiB safety ceiling
});
defer dec.deinit();
```

## Reusable Context (`reset`)

To decompress a sequence of Brotli streams without repeatedly allocating ring buffers and lookup tables, reset the context between streams:

```zig
pub fn reset(self: *Decompressor, options: ?DecompressionOptions) void
pub fn resetForNewStream(self: *Decompressor) void
```

`reset(opts)` resets the decoder and optionally applies new configuration options while preserving ring buffer allocations. `resetForNewStream()` prepares the state machine for the next stream with the same options.

```zig
for (compressed_files) |stream| {
    dec.reset(null);
    const decoded = try dec.decompress(stream);
    defer allocator.free(decoded);
    // Process decoded data...
}
```

## Context-Level Decompression

### `decompress`

```zig
pub fn decompress(self: *Decompressor, input: []const u8) ![]u8
```

Decompresses the complete input stream into a newly allocated buffer using the context's internal ring buffers and options. The caller owns the returned slice.

### `decompressInto`

```zig
pub fn decompressInto(self: *Decompressor, input: []const u8, output: []u8) !usize
```

Decompresses directly into a caller-provided destination slice. Returns the exact number of uncompressed bytes produced.

```zig
var out_buf: [16384]u8 = undefined;
const bytes_written = try dec.decompressInto(compressed_slice, &out_buf);
const result = out_buf[0..bytes_written];
```

## Low-Level Streaming (`decompressStream`)

```zig
pub fn decompressStream(
    self: *Decompressor,
    next_in: *[]const u8,
    available_out: *[]u8,
    total_out: ?*u64,
) DecodeResult
```

- `next_in`: Pointer to remaining compressed input slice. The slice is advanced past consumed bytes.
- `available_out`: Pointer to destination output slice. The slice is updated to point to remaining available capacity.
- `total_out`: Optional cumulative counter of uncompressed bytes produced so far.

### `DecodeResult` Enumeration

| Result | Meaning | Action Needed |
|---|---|---|
| `.success` | Entire stream successfully decoded | Done; stream is complete |
| `.needs_more_input` | Decoder consumed available input and expects more | Provide more compressed bytes |
| `.needs_more_output` | Destination buffer is full; uncompressed bytes remain | Drain destination and call again |
| `.err` | Stream corruption or fatal decoding error | Query `dec.errorCode()` |

### Streaming Loop Example

```zig
var in_remaining: []const u8 = compressed_data;
var out_buf: [16384]u8 = undefined;

while (true) {
    var avail_out: []u8 = &out_buf;
    const result = dec.decompressStream(&in_remaining, &avail_out, null);

    const produced = out_buf.len - avail_out.len;
    if (produced > 0) {
        try dest_stream.writeAll(out_buf[0..produced]);
    }

    switch (result) {
        .success => break,
        .needs_more_output => continue,
        .needs_more_input => {
            if (in_remaining.len == 0) return error.TruncatedInput;
            continue;
        },
        .err => return dec.errorCode().toError(),
    }
}
```

## Custom Dictionary Attachment

```zig
pub fn attachDictionary(self: *Decompressor, data: []const u8) bool
```

Attaches raw dictionary bytes that serve as back-reference history matching the dictionary used during compression. Must be called before decoding the first byte of the stream.

## Detailed Error Code Inspection

```zig
pub fn errorCode(self: *const Decompressor) ErrorCode
```

When `decompressStream` returns `.err`, inspect the exact RFC 7932 failure reason:

```zig
const code = dec.errorCode();
std.debug.print("Failed: {s} (code: {d})\n", .{ code.name(), @intFromEnum(code) });
```

See [Errors](/api/errors) for the complete list of error codes.

## State Queries

```zig
pub fn hasMoreOutput(self: *const Decompressor) bool
pub fn isUsed(self: *const Decompressor) bool
pub fn isFinished(self: *const Decompressor) bool
```

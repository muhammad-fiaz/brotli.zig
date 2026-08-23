---
title: Decoder
description: Streaming decoder with detailed error reporting and dictionary support.
---

# Decoder

The streaming decoder. Feed compressed input, drain decoded output.
Defined in `src/decompress/decode.zig` and re-exported as
`brotli.Decoder`.

## Creation

```zig
pub fn init(allocator: std.mem.Allocator, options: DecoderOptions) Decoder
```

```zig
var d = brotli.Decoder.init(allocator, .{});
defer d.deinit();
```

## Streaming

```zig
pub fn decompressStream(
    self: *Decoder,
    next_in: *[]const u8,       // advanced past consumed input
    available_out: *[]u8,       // shrunk by written bytes
    total_out: ?*u64,           // receives cumulative output size
) Result
```

Returns `.success`, `.needs_more_input`, `.needs_more_output`, or `.err`.
Input is never over-consumed; pass the remaining slice back on the next call.

```zig
var in: []const u8 = compressed;
var out_buf: [65536]u8 = undefined;
while (true) {
    var avail: []u8 = &out_buf;
    var total: u64 = 0;
    switch (d.decompressStream(&in, &avail, &total)) {
        .success => break,
        .needs_more_output => {},
        .needs_more_input => return error.Truncated,
        .err => return error.Corrupt,
    }
}
```

## Custom Dictionary

```zig
pub fn attachDictionary(self: *Decoder, data: []const u8) bool
```

Must precede the first input byte. Data is referenced (not copied) and must
outlive the decoder. Streams produced with the identical dictionary attached
to the encoder decode correctly.

## Diagnostics

```zig
pub fn errorCode(self: *const Decoder) ErrorCode
// ErrorCode.name() mirrors BrotliDecoderErrorStr values
if (r == .err) {
    std.debug.print("decoder failed: {s}\n", .{d.errorCode().name()});
}
```

## Metadata Callbacks

`brotli.MetadataCallbacks` registers observers for metadata blocks (mirrors
`BrotliDecoderSetMetadataCallbacks`).

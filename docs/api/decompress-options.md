---
title: DecompressionOptions
description: Options struct for the brotli decoder.
---

# DecompressionOptions

Options for `brotli.Decoder` and `brotli.StreamingDecompressor`. Defined in
`src/decompress/decode.zig`, re-exported as `brotli.DecoderOptions` /
`brotli.DecompressionOptions`.

## Definition

```zig
pub const Options = struct {
    /// Accept Large Window Brotli streams (LGWIN up to 30).
    large_window: bool = false,
};
```

## Usage

```zig
var d = brotli.Decoder.init(allocator, .{ .large_window = true });
defer d.deinit();
```

Streams declaring a standard window (16..24) decode with or without the
flag; only large-window streams (`lgwin` 25..30) require it.

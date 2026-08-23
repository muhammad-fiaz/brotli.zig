---
title: Dictionaries
description: Static and custom dictionary support.
---

# Dictionaries

Brotli uses dictionaries in two ways:

1. **Built-in static dictionary** — the 122,784-byte RFC 7932 word list,
   embedded in the library. Decoding works out of the box; no setup needed.
2. **Custom raw dictionaries** — user-supplied bytes attached to both the
   encoder and decoder, enabling compact back-references for small payloads
   that overlap a shared corpus.

## Custom Dictionary (Encoder)

```zig
var enc = brotli.Encoder.init(allocator, .{ .quality = 11 });
defer enc.deinit();
if (!enc.attachDictionary(my_dict_bytes)) return error.InvalidDictionary;
// Must be called before the first compressStream.
```

Rules:
- Data is **referenced, not copied** — it must outlive the encoder.
- Maximum size is 16 MiB (`1 << 24`).
- Empty data is a soft no-op (returns true).

## Custom Dictionary (Decoder)

```zig
var d = brotli.Decoder.init(allocator, .{});
defer d.deinit();
if (!d.attachDictionary(my_dict_bytes)) return error.InvalidDictionary;
```

Must be called before any input is fed. The bytes must be **identical** to
those given to the encoder, otherwise references resolve incorrectly.

## Streaming

```zig
var sc = brotli.StreamingCompressor.init(allocator, .{});
defer sc.deinit();
try testing.expect(sc.attachDictionary(dict));
// then process()/finish() as usual
```

## How It Works

Dictionary content acts as history that precedes the output: LZ77 matches
may reach backward into it. On the wire these are ordinary explicit
distances; the decoder resolves them through its compound-dictionary path
(mirroring `BrotliDecoderAttachDictionary` semantics). Streams produced with
a dictionary cannot be decoded without it.

## Static Dictionary

The built-in word list requires no configuration on either side — decoding
any conforming stream automatically resolves its word/transform references
through `src/dictionary/dictionary.zig`.

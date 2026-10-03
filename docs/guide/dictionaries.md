---
title: Dictionaries
description: Shared custom dictionaries for small-payload compression.
---

# Dictionaries

Attach identical raw dictionary bytes to encoder and decoder:

## Encoder

```zig
var enc = brotli.Encoder.init(allocator, .{});
defer enc.deinit();
if (!enc.attachDictionary(dict_bytes)) return error.InvalidDictionary;
// must precede first compressStream
```

## Decoder

```zig
var d = brotli.Decoder.init(allocator, .{});
defer d.deinit();
if (!d.attachDictionary(dict_bytes)) return error.InvalidDictionary;
// must precede first input byte
```

## Shared and Compound Dictionaries

For multi-chunk or compound dictionaries, use `brotli.SharedDictionary`:

```zig
var dict = brotli.SharedDictionary.init(allocator);
defer dict.deinit();

_ = dict.attach(.raw, prefix_chunk_1);
_ = dict.attach(.raw, prefix_chunk_2);

const compressed = try brotli.compressWithSharedDictionary(allocator, payload, &dict, .{ .quality = 9 });
defer allocator.free(compressed);

const original = try brotli.decompressWithSharedDictionary(allocator, compressed, &dict, .{});
defer allocator.free(original);
```

## Notes

- Data is referenced, not copied - keep it alive.
- Max size: 16 MiB.
- Supports up to 15 compound chunks with `brotli.SharedDictionary`.
- Streams produced with a dict cannot be decoded without it.
- The RFC 7932 static dictionary is built in on both sides automatically.

Full walkthrough: [Dictionary Compression](../examples/dictionary_compression).
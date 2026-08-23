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

## Notes

- Data is referenced, not copied — keep it alive.
- Max size: 16 MiB.
- Streams produced with a dict cannot be decoded without it.
- The RFC 7932 static dictionary is built in on both sides automatically.

Full walkthrough: [Dictionary Compression](../examples/dictionary_compression).
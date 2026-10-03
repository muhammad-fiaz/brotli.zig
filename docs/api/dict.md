---
title: Dictionaries
description: Built-in RFC 7932 static dictionary and custom shared dictionary support in brotli.zig.
---

# Dictionaries

Brotli utilizes two distinct dictionary mechanisms to dramatically improve compression ratios, particularly on small messages and structured documents:

1. **RFC 7932 Built-In Static Dictionary**: Embedded directly into the library (122,784 bytes of common English, HTML, XML, and punctuation fragments). Always available out of the box with zero runtime setup or transmission overhead.
2. **Custom Raw Dictionaries**: User-supplied shared corpora (up to 16 MiB) attached to both the encoder and decoder.

## Using Custom Dictionaries via Options

The simplest method is passing `customDictionary` in options:

### Compression

```zig
const brotli = @import("brotli");

const dict = "{\"status\":200,\"message\":\"ok\",\"data\":[";
const json_payload = "{\"status\":200,\"message\":\"ok\",\"data\":[{\"id\":1}]}";

const compressed = try brotli.compressWithOptions(allocator, json_payload, .{
    .quality = 11,
    .customDictionary = dict,
});
defer allocator.free(compressed);
```

### Decompression

```zig
const decompressed = try brotli.decompressWithOptions(allocator, compressed, .{
    .customDictionary = dict,
});
defer allocator.free(decompressed);

try std.testing.expectEqualStrings(json_payload, decompressed);
```

## Attaching Dictionaries to Contexts

You can also attach a dictionary dynamically to `Compressor`, `Decompressor`, or `StreamingCompressor`:

### `Compressor.attachDictionary`

```zig
var comp = brotli.Compressor.init(allocator, .{ .quality = 9 });
defer comp.deinit();

if (!comp.attachDictionary(shared_corpus)) {
    return error.InvalidDictionary;
}

// Compress data referencing shared_corpus...
```

### `Decompressor.attachDictionary`

```zig
var dec = brotli.Decompressor.init(allocator, .{});
defer dec.deinit();

if (!dec.attachDictionary(shared_corpus)) {
    return error.InvalidDictionary;
}

// Decompress streams produced with shared_corpus...
```

## Shared and Compound Dictionaries (`brotli.SharedDictionary`)

For multi-chunk compound dictionary scenarios, `brotli.SharedDictionary` manages up to 15 chunks (`MAX_COMPOUND_DICTS = 15`) and up to 16 MiB total size:

```zig
const brotli = @import("brotli");

var dict = brotli.SharedDictionary.init(allocator);
defer dict.deinit();

_ = dict.attach(.raw, "prefix_chunk_one");
_ = dict.attach(.raw, "prefix_chunk_two");

// One-shot helpers
const compressed = try brotli.compressWithSharedDictionary(allocator, payload, &dict, .{ .quality = 9 });
defer allocator.free(compressed);

const decompressed = try brotli.decompressWithSharedDictionary(allocator, compressed, &dict, .{});
defer allocator.free(decompressed);
```

### Streaming with Shared Dictionaries

Attach `SharedDictionary` instances directly to streaming codecs:

```zig
// Streaming compressor
var sc = brotli.StreamingCompressor.init(allocator, .{ .quality = 7 });
defer sc.deinit();
_ = sc.attachSharedDictionary(&dict);

// Streaming decompressor
var sd = brotli.StreamingDecompressor.init(allocator, .{});
defer sd.deinit();
_ = sd.attachSharedDictionary(&dict);
```

## Rules and Operational Constraints

- **Exact Match Required**: The decoder must receive the byte-for-byte identical dictionary that was attached during compression.
- **Reference Semantics**: Dictionary memory is referenced (not copied). The slice must outlive the compression/decompression operations.
- **Call Order**: When using context objects, `attachDictionary()` or `attachSharedDictionary()` must be called **before** any input data is fed.
- **Maximum Size**: Up to 16 MiB (`1 << 24` bytes, per RFC 7932 compound dictionary rules).

## Built-In Static Dictionary (`brotli.Dictionary`)

The RFC 7932 static dictionary is implemented in `src/dictionary/dictionary.zig` and re-exported as `brotli.Dictionary`:

```zig
pub const data: []const u8           // 122,784 bytes of raw static dictionary
pub const size: usize = 122784;
```

It requires no explicit setup; any standard Brotli stream referencing words or transforms in the static dictionary resolves them automatically.

---
title: IO Pipeline
description: In-memory, caller-buffer, reader/writer, and chunked streaming shapes.
---

# `io_pipeline`

Compresses and decompresses the same payload through all four client-side I/O
shapes and checks that every one of them produces identical bytes.

```bash
zig build run-io_pipeline
```

## The four shapes

### In-memory one-shot

The caller owns the input slice and receives an allocated result.

```zig
const compressed = try brotli.compressWithOptions(allocator, input, .{ .quality = 9 });
defer allocator.free(compressed);

const decoded = try brotli.decompress(allocator, compressed);
defer allocator.free(decoded);
```

Both returned slices belong to the caller and must be freed with the same
allocator that was passed in.

### Caller-provided destination

Use `decompressInto` when the output buffer already exists, so the
decompression side performs no allocation at all.

```zig
var buffer: [output_size]u8 = undefined;
const written = try brotli.decompressInto(allocator, compressed, buffer);
```

`written` is the number of valid bytes in `buffer`. The function fails rather
than overflowing when the destination is too small.

### Explicit reader and writer

Hand the codec real endpoints and let it move bytes between them. The caller
keeps ownership of both.

```zig
var reader = std.Io.Reader.fixed(input);
var writer = std.Io.Writer.fixed(&out_buffer);
try brotli.compressStream(allocator, &reader, &writer, .{ .quality = 9 });
try writer.flush();

var comp_reader = std.Io.Reader.fixed(writer.buffered());
var out_writer = std.Io.Writer.fixed(&decompressed);
try brotli.decompressStream(allocator, &comp_reader, &out_writer, .{});
try out_writer.flush();
```

Neither call assumes a single read or write transfers everything: partial
reads and partial writes are handled internally, and the endpoints stay owned
by the caller.

### Chunked streaming adapters

`StreamingCompressor` and `StreamingDecompressor` move fixed-size windows, so
peak memory stays bounded regardless of payload size.

```zig
var compressor = brotli.StreamingCompressor.init(allocator, .{ .quality = 9 });
defer compressor.deinit();

const piece = try compressor.process(chunk);   // caller frees `piece`
defer allocator.free(piece);
const tail = try compressor.finishAlloc();     // end-of-stream bytes
defer allocator.free(tail);
```

On the decoding side, `feed` accepts input chunks and `take` hands back
whatever is ready:

```zig
var decompressor = brotli.StreamingDecompressor.init(allocator, .{});
defer decompressor.deinit();

try decompressor.feed(chunk);
const n = try decompressor.take(&out_buffer);
```

When a call reports that it needs more input, keep calling it: the decoder may
still hold buffered bytes that have not been consumed yet. Poll until
`isFinished()` is true and `take` returns zero.

## Ownership summary

| Shape | Input ownership | Output ownership |
|---|---|---|
| One-shot | borrowed | allocated, caller frees |
| Caller buffer | borrowed | caller-provided slice |
| Reader/writer | caller-owned endpoints | caller-owned endpoints |
| Chunked adapters | caller-owned chunks | allocated pieces, caller frees |
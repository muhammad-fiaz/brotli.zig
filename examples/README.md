# brotli.zig Examples

This directory contains standalone examples demonstrating the brotli.zig API.

## Running Examples

Build all examples:

```bash
zig build examples
```

Run a specific example:

```bash
zig run examples/01_quick_compress.zig --deps brotli
```

## Example List

**01_quick_compress.zig** - Minimal compress and decompress using the top-level convenience functions.

**02_custom_quality.zig** - Using `compressWithOptions` with custom quality, lgwin, and mode settings.

**03_streaming_encode.zig** - Chunked input through the streaming `Encoder.compressStream` API.

**04_streaming_decode.zig** - Chunked decompression through the streaming `Decoder.decompressStream` API.

**05_custom_allocator.zig** - Passing a non-default allocator (arena) through the bridge.

**06_shared_dictionary.zig** - Using `PreparedDictionary` with the encoder.

**07_large_window.zig** - Large window mode with lgwin > 24 on both encoder and decoder.

**08_error_handling.zig** - Deliberately feeding corrupt input and inspecting the error result.

# brotli.zig Examples

This directory contains standalone examples demonstrating the brotli.zig API.

## Running Examples

Build all examples:

```bash
zig build examples
```

Run a specific example after building:

```bash
./zig-out/bin/01_quick_compress
```

## Example List

| # | File | Description |
|---|---|---|
| 01 | `01_quick_compress.zig` | Minimal one-shot compress/decompress using top-level convenience functions |
| 02 | `02_custom_quality.zig` | Using `compressWithOptions` with custom quality, lgwin, and mode settings |
| 03 | `03_streaming_encode.zig` | Chunked input through the streaming `Encoder.compressStream` API |
| 04 | `04_streaming_decode.zig` | Chunked decompression through the streaming `Decoder.decompressStream` API |
| 05 | `05_custom_allocator.zig` | Passing a non-default allocator (arena) through the C allocator bridge |
| 06 | `06_shared_dictionary.zig` | Using `PreparedDictionary` with the encoder for better compression |
| 07 | `07_large_window.zig` | Large window mode with lgwin > 24 on both encoder and decoder |
| 08 | `08_error_handling.zig` | Deliberately feeding corrupt input and inspecting the error result |
| 09 | `09_metadata.zig` | Emitting metadata blocks with the streaming encoder |
| 10 | `10_base64_mode.zig` | Using base64 detection mode for better compression of base64 data |

## API Features Demonstrated

- **One-shot compression**: `brotli.compress`, `brotli.decompress`
- **Streaming compression**: `Encoder.compressStream` with `.process`, `.flush`, `.finish` operations
- **Streaming decompression**: `Decoder.decompressStream` with result handling
- **Custom allocator**: Arena allocator through the C allocator bridge
- **Prepared dictionary**: `PreparedDictionary` for dictionary-assisted compression
- **Large window mode**: `EncoderOptions.large_window` with lgwin > 24
- **Error handling**: `error.DecompressionFailed` on corrupt input
- **Custom quality**: `EncoderOptions.quality` (0-11), `EncoderOptions.lgwin`, `EncoderOptions.mode`
- **Metadata blocks**: `EncoderOperation.emit_metadata` for custom metadata
- **Base64 mode**: `EncoderOptions.base64_mode` and `EncoderOptions.max_base64_regions`

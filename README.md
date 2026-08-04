<div align="center">

# brotli.zig

<a href="https://ziglang.org/"><img src="https://img.shields.io/badge/Zig-0.16.0-orange.svg?logo=zig" alt="Zig Version"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig"><img src="https://img.shields.io/github/stars/muhammad-fiaz/brotli.zig" alt="GitHub stars"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/issues"><img src="https://img.shields.io/github/issues/muhammad-fiaz/brotli.zig" alt="GitHub issues"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/pulls"><img src="https://img.shields.io/github/issues-pr/muhammad-fiaz/brotli.zig" alt="GitHub pull requests"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig"><img src="https://img.shields.io/github/last-commit/muhammad-fiaz/brotli.zig" alt="GitHub last commit"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/actions/workflows/ci.yml"><img src="https://github.com/muhammad-fiaz/brotli.zig/actions/workflows/ci.yml/badge.svg?branch=master" alt="CI"></a>
<img src="https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macos-blue" alt="Supported Platforms">
<a href="https://github.com/muhammad-fiaz/brotli.zig/releases/latest"><img src="https://img.shields.io/github/v/release/muhammad-fiaz/brotli.zig?label=Latest%20Release&style=flat-square" alt="Latest Release"></a>
<a href="https://hits.sh/muhammad-fiaz/brotli.zig/"><img src="https://hits.sh/muhammad-fiaz/brotli.zig.svg?label=Visitors&extraCount=0&color=green" alt="Repo Visitors"></a>

<p><em>High-level native Zig bindings for Google's Brotli fast compression library.</em></p>

<b><a href="#installation">Installation</a> |
<a href="#quick-start">Quick Start</a> |
<a href="#api-coverage">API Coverage</a> |
<a href="#examples">Examples</a> |
<a href="CONTRIBUTING.md">Contributing</a> |
<a href="#license">License</a></b>

</div>

---

High-level native Zig bindings for Google's [Brotli](https://github.com/google/brotli) fast compression library. Wraps the full Brotli C API (`encode.h`, `decode.h`, `types.h`, `shared_dictionary.h`) into idiomatic, safe, well-documented Zig modules with **100% API coverage**.

## Requirements

- Zig 0.16.0 or later

## Installation

### Option 1: Stable Release (Recommended)

```bash
zig fetch --save https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/0.0.1.tar.gz
```

Or add directly to your `build.zig.zon`:

```zig
.dependencies = .{
    .brotli = .{
        .url = "https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/0.0.1.tar.gz",
        .hash = "...", // Run `zig build` to obtain the hash
    },
},
```

### Option 2: Nightly

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/brotli.zig.git
```

### Option 3: Local Path

```bash
git clone https://github.com/muhammad-fiaz/brotli.zig.git
```

Then reference from your `build.zig.zon`:

```zig
.dependencies = .{
    .brotli = .{
        .path = "/path/to/brotli.zig",
    },
},
```

### Importing

In your `build.zig`:

```zig
const brotli_dep = b.dependency("brotli", .{});
exe.root_module.addImport("brotli", brotli_dep.module("brotli"));
```

In your Zig source:

```zig
const brotli = @import("brotli");
```

## Quick Start

### Compress and Decompress

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const data = "Hello, Brotli from Zig!";

    const compressed = try brotli.compress(std.heap.c_allocator, data);
    defer std.heap.c_allocator.free(compressed);

    const decompressed = try brotli.decompress(std.heap.c_allocator, compressed);
    defer std.heap.c_allocator.free(decompressed);

    std.debug.print("Compressed {d} -> {d} bytes\n", .{ data.len, compressed.len });
}
```

### Streaming Compression

```zig
var enc = try brotli.encoder.Encoder.init(allocator, .{ .quality = 6 });
defer enc.deinit();

var output: [4096]u8 = undefined;
const result = try enc.compressStream(.finish, data, &output);
const compressed_data = output[0..result.bytes_produced];
```

### Dictionary Compression

```zig
const dict_data = "shared dictionary context";

var prepared = try brotli.PreparedDictionary.init(allocator, .raw, dict_data, 11);
defer prepared.deinit();

var enc = try brotli.encoder.Encoder.init(allocator, .{ .quality = 6 });
defer enc.deinit();

try enc.attachPreparedDictionary(&prepared);
```

## API Coverage

Every public C function from `encode.h`, `decode.h`, `types.h`, and `shared_dictionary.h` is bound:

### Encoder Functions

| C Function | Zig Binding | Description |
|---|---|---|
| `BrotliEncoderCreateInstance` | `Encoder.init` | Create encoder instance |
| `BrotliEncoderDestroyInstance` | `Encoder.deinit` | Destroy encoder instance |
| `BrotliEncoderSetParameter` | `Encoder.setParameter` / `EncoderOptions.apply` | Set encoder parameter |
| `BrotliEncoderCompress` | `oneshot.compress` / `brotli.compress` | One-shot compression |
| `BrotliEncoderCompressStream` | `Encoder.compressStream` | Streaming compression |
| `BrotliEncoderIsFinished` | `Encoder.isFinished` | Check if stream is finished |
| `BrotliEncoderHasMoreOutput` | `Encoder.hasMoreOutput` | Check if more output available |
| `BrotliEncoderTakeOutput` | `Encoder.takeOutput` | Take output from encoder |
| `BrotliEncoderMaxCompressedSize` | Used internally by `oneshot.compress` | Get max compressed size |
| `BrotliEncoderVersion` | `brotli.version()` | Get encoder library version |
| `BrotliEncoderPrepareDictionary` | `PreparedDictionary.init` | Prepare dictionary for encoding |
| `BrotliEncoderDestroyPreparedDictionary` | `PreparedDictionary.deinit` | Destroy prepared dictionary |
| `BrotliEncoderAttachPreparedDictionary` | `Encoder.attachPreparedDictionary` | Attach prepared dictionary |
| `BrotliEncoderEstimatePeakMemoryUsage` | `Encoder.estimatePeakMemoryUsage` | Estimate peak memory usage |

### Decoder Functions

| C Function | Zig Binding | Description |
|---|---|---|
| `BrotliDecoderCreateInstance` | `Decoder.init` | Create decoder instance |
| `BrotliDecoderDestroyInstance` | `Decoder.deinit` | Destroy decoder instance |
| `BrotliDecoderSetParameter` | `Decoder.setParameter` / `DecoderOptions.apply` | Set decoder parameter |
| `BrotliDecoderDecompressStream` | `Decoder.decompressStream` / `oneshot.decompress` | Streaming decompression |
| `BrotliDecoderHasMoreOutput` | `Decoder.hasMoreOutput` | Check if more output available |
| `BrotliDecoderTakeOutput` | `Decoder.takeOutput` | Take output from decoder |
| `BrotliDecoderIsUsed` | `Decoder.isUsed` | Check if decoder has been used |
| `BrotliDecoderIsFinished` | `Decoder.isFinished` | Check if decoding is finished |
| `BrotliDecoderGetErrorCode` | `Decoder.getErrorCode` | Get error code after failure |
| `BrotliDecoderErrorString` | `Decoder.errorString` | Get human-readable error string |
| `BrotliDecoderVersion` | `brotli.version()` | Get decoder library version |
| `BrotliDecoderAttachDictionary` | `Decoder.attachDictionary` | Attach shared dictionary |
| `BrotliDecoderSetMetadataCallbacks` | Not bound (internal use) | Set metadata callbacks |

### Shared Dictionary Functions

| C Function | Zig Binding | Description |
|---|---|---|
| `BrotliSharedDictionaryCreateInstance` | `SharedDictionary.init` | Create shared dictionary |
| `BrotliSharedDictionaryDestroyInstance` | `SharedDictionary.deinit` | Destroy shared dictionary |
| `BrotliSharedDictionaryAttach` | `SharedDictionary.attach` | Attach data to dictionary |

### Encoder Parameters

| C Parameter | Zig Field | Type | Range |
|---|---|---|---|
| `BROTLI_PARAM_MODE` | `EncoderOptions.mode` | `EncoderMode` | `.generic`, `.text`, `.font` |
| `BROTLI_PARAM_QUALITY` | `EncoderOptions.quality` | `?u4` | 0-11 |
| `BROTLI_PARAM_LGWIN` | `EncoderOptions.lgwin` | `?u5` | 10-24 (or 10-30 large window) |
| `BROTLI_PARAM_LGBLOCK` | `EncoderOptions.lgblock` | `?u5` | 16-24 |
| `BROTLI_PARAM_DISABLE_LITERAL_CONTEXT_MODELING` | `EncoderOptions.disable_literal_context_modeling` | `?bool` | true/false |
| `BROTLI_PARAM_SIZE_HINT` | `EncoderOptions.size_hint` | `?usize` | any |
| `BROTLI_PARAM_LARGE_WINDOW` | `EncoderOptions.large_window` | `?bool` | true/false |
| `BROTLI_PARAM_NPOSTFIX` | `EncoderOptions.npostfix` | `?u2` | 0-3 |
| `BROTLI_PARAM_NDIRECT` | `EncoderOptions.ndirect` | `?u7` | 0-127 |
| `BROTLI_PARAM_STREAM_OFFSET` | `EncoderOptions.stream_offset` | `?usize` | any |
| `BROTLI_PARAM_BASE64_MODE` | `EncoderOptions.base64_mode` | `?u1` | 0-1 |
| `BROTLI_PARAM_MAX_BASE64_REGIONS` | `EncoderOptions.max_base64_regions` | `?u4` | 0-15 |

### Decoder Parameters

| C Parameter | Zig Field | Type |
|---|---|---|
| `BROTLI_DECODER_PARAM_DISABLE_RING_BUFFER_REALLOCATION` | `DecoderOptions.disable_ring_buffer_reallocation` | `?bool` |
| `BROTLI_DECODER_PARAM_LARGE_WINDOW` | `DecoderOptions.large_window` | `?bool` |

### Enums

| C Enum | Zig Type | Values |
|---|---|---|
| `BrotliEncoderMode` | `EncoderMode` | `generic` (0), `text` (1), `font` (2) |
| `BrotliEncoderBase64Mode` | `EncoderBase64Mode` | `disabled` (0), `detection` (1) |
| `BrotliEncoderParameter` | `EncoderParameter` | `mode`, `quality`, `lgwin`, `lgblock`, `disable_literal_context_modeling`, `size_hint`, `large_window`, `npostfix`, `ndirect`, `stream_offset`, `base64_mode`, `max_base64_regions` |
| `BrotliEncoderOperation` | `EncoderOperation` | `process` (0), `flush` (1), `finish` (2), `emit_metadata` (3) |
| `BrotliDecoderParameter` | `DecoderParameter` | `disable_ring_buffer_reallocation` (0), `large_window` (1) |
| `BrotliDecoderResult` | `DecoderResult` | tagged union: `success`, `needs_more_input`, `needs_more_output`, `error(DecodeError)` |
| `BrotliDecoderErrorCode` | `ErrorCode` | 31 error codes (no_error through error_unreachable) |
| `BrotliSharedDictionaryType` | `DictionaryType` | `raw` (0), `serialized` (1) |

### Error Types

| Zig Type | Error Set |
|---|---|
| `EncoderError` | `OutOfMemory`, `InvalidParameter` |
| `DecoderError` | `OutOfMemory`, `DecompressionFailed` |
| `DictionaryError` | `OutOfMemory`, `InvalidDictionary` |

## Module Overview

| Module | Description |
|---|---|
| `brotli` | Public root with convenience functions (`compress`, `decompress`, `version`) and all constants/enums |
| `brotli.encoder.Encoder` | Streaming encoder with full parameter coverage |
| `brotli.encoder.PreparedDictionary` | Prepared dictionary for encoder with `getSize()` |
| `brotli.encoder.EncoderOptions` | Typed encoder parameter struct (12 optional fields) |
| `brotli.encoder.oneshot` | One-shot compression via `BrotliEncoderCompress` |
| `brotli.decoder.Decoder` | Streaming decoder with `decompressStream`, `decompressBuffer`, `attachDictionary`, `setMetadataCallbacks` |
| `brotli.decoder.DecoderOptions` | Typed decoder parameter struct (2 optional fields) |
| `brotli.decoder.oneshot` | One-shot decompression via `BrotliDecoderDecompressStream` loop |
| `brotli.common.types` | All enums: `EncoderMode`, `EncoderBase64Mode`, `EncoderParameter`, `EncoderOperation`, `DecoderParameter`, `DecoderResult`, `ErrorCode`, `DictionaryType`; all constants; error sets |
| `brotli.common.allocator` | Zig `std.mem.Allocator` to Brotli C allocator bridge (`CAllocator`) |
| `brotli.common.dictionary` | `SharedDictionary` wrapper |
| `brotli.version` | `version.encoder()` and `version.decoder()` |

## Examples

See the [examples/](examples/) directory for complete, runnable programs:

| Example | Description |
|---|---|
| `01_quick_compress.zig` | Minimal one-shot compress/decompress |
| `02_custom_quality.zig` | Custom quality, lgwin, and mode settings |
| `03_streaming_encode.zig` | Chunked streaming encoder |
| `04_streaming_decode.zig` | Chunked streaming decoder |
| `05_custom_allocator.zig` | Arena allocator usage |
| `06_shared_dictionary.zig` | PreparedDictionary with encoder |
| `07_large_window.zig` | Large window mode (lgwin > 24) |
| `08_error_handling.zig` | Corrupt input error handling |
| `09_metadata.zig` | Emitting metadata blocks |
| `10_base64_mode.zig` | Base64 detection mode |

## Building & Testing

```bash
zig build            # Build library
zig build test       # Run all tests (112 tests)
zig build examples   # Build all examples
```

### Build Options

| Option | Default | Description |
|---|---|---|
| `-Dportable` | `false` | Build with `BROTLI_BUILD_PORTABLE=1` |
| `-Dshared` | `false` | Build Brotli as a shared library instead of static |

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT - see [LICENSE](LICENSE).

Original Brotli code: Copyright (c) 2009, 2010, 2013-2016 by the Brotli Authors (Google).

Zig bindings: Copyright (c) 2026 Muhammad Fiaz.

## Author

**Muhammad Fiaz** - Zig bindings, build system, and API design

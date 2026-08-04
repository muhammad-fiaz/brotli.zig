<div align="center">

# brotli.zig

<a href="https://ziglang.org/"><img src="https://img.shields.io/badge/Zig-0.16.0-orange.svg?logo=zig" alt="Zig Version"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig"><img src="https://img.shields.io/github/stars/muhammad-fiaz/brotli.zig" alt="GitHub stars"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/issues"><img src="https://img.shields.io/github/issues/muhammad-fiaz/brotli.zig" alt="GitHub issues"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/pulls"><img src="https://img.shields.io/github/issues-pr/muhammad-fiaz/brotli.zig" alt="GitHub pull requests"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig"><img src="https://img.shields.io/github/last-commit/muhammad-fiaz/brotli.zig" alt="GitHub last commit"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/blob/main/LICENSE"><img src="https://img.shields.io/github/license/muhammad-fiaz/brotli.zig" alt="License"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/actions/workflows/ci.yml"><img src="https://github.com/muhammad-fiaz/brotli.zig/actions/workflows/ci.yml/badge.svg?branch=master" alt="CI"></a>
<img src="https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macos-blue" alt="Supported Platforms">
<a href="https://github.com/muhammad-fiaz/brotli.zig/releases/latest"><img src="https://img.shields.io/github/v/release/muhammad-fiaz/brotli.zig?label=Latest%20Release&style=flat-square" alt="Latest Release"></a>
<a href="https://hits.sh/muhammad-fiaz/brotli.zig/"><img src="https://hits.sh/muhammad-fiaz/brotli.zig.svg?label=Visitors&extraCount=0&color=green" alt="Repo Visitors"></a>

<p><em>High-level native Zig bindings for Google's Brotli fast compression library.</em></p>

<b><a href="#installation">Installation</a> |
<a href="#quick-start">Quick Start</a> |
<a href="#feature-coverage">Features</a> |
<a href="CONTRIBUTING.md">Contributing</a> |
<a href="#license">License</a></b>

</div>

---

High-level native Zig bindings for Google's [Brotli](https://github.com/google/brotli) fast compression library. Wraps the full Brotli C API (`encode.h`, `decode.h`, `types.h`, `shared_dictionary.h`) into idiomatic, safe, well-documented Zig modules.

> [!NOTE]
> These bindings track and are upstreamed against Google Brotli [commit `0d1f629`](https://github.com/google/brotli/commits/master/0d1f6297d6a4f6e2acd5e50ae9a5d22c3f55ba6d).

## Requirements

> [!NOTE]
> * Zig 0.16.0 or later is required.

## Installation

### Option 1: Stable Release (Recommended)

Install the latest stable release from the official release archive:

```bash
zig fetch --save https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/0.0.1.tar.gz
```

Or add it directly to your `build.zig.zon`:

```zig
.dependencies = .{
    .brotli = .{
        .url = "https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/0.0.1.tar.gz",
        .hash = "...", // Run `zig build` to obtain the hash
    },
},
```

---

### Option 2: Nightly

Track the latest development version from the repository:

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/brotli.zig.git
```

Or pin to a specific commit:

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/brotli.zig.git#COMMIT_HASH
```

Or add it to your `build.zig.zon`:

```zig
.dependencies = .{
    .brotli = .{
        .url = "git+https://github.com/muhammad-fiaz/brotli.zig.git#COMMIT_HASH",
        .hash = "...", // Run `zig build` to obtain the hash
    },
},
```

---

### Option 3: Local Path

Clone the repository:

```bash
git clone https://github.com/muhammad-fiaz/brotli.zig.git
```

Then reference it from your `build.zig.zon`:

```zig
.dependencies = .{
    .brotli = .{
        .path = "/path/to/brotli.zig",
    },
},
```

---

### Importing

After adding the dependency, import the module in your `build.zig`:

```zig
const brotli_dep = b.dependency("brotli", .{});
exe.root_module.addImport("brotli", brotli_dep.module("brotli"));
```

Then use it in your Zig source:

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

    // Compress
    const compressed = try brotli.compress(std.heap.c_allocator, data);
    defer std.heap.c_allocator.free(compressed);

    // Decompress
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

## Feature Coverage

| Feature | Supported | Native Symbol | Zig Entry Point |
|---|---|---|---|
| Encoder Mode (generic/text/font) | Yes | `BROTLI_PARAM_MODE` | `EncoderOptions.mode` |
| Quality (0-11) | Yes | `BROTLI_PARAM_QUALITY` | `EncoderOptions.quality` |
| Window Size (lgwin) | Yes | `BROTLI_PARAM_LGWIN` | `EncoderOptions.lgwin` |
| Block Size (lgblock) | Yes | `BROTLI_PARAM_LGBLOCK` | `EncoderOptions.lgblock` |
| Disable Literal Context Modeling | Yes | `BROTLI_PARAM_DISABLE_LITERAL_CONTEXT_MODELING` | `EncoderOptions.disable_literal_context_modeling` |
| Size Hint | Yes | `BROTLI_PARAM_SIZE_HINT` | `EncoderOptions.size_hint` |
| Large Window Mode | Yes | `BROTLI_PARAM_LARGE_WINDOW` | `EncoderOptions.large_window` |
| NPostfix | Yes | `BROTLI_PARAM_NPOSTFIX` | `EncoderOptions.npostfix` |
| NDirect | Yes | `BROTLI_PARAM_NDIRECT` | `EncoderOptions.ndirect` |
| Stream Offset | Yes | `BROTLI_PARAM_STREAM_OFFSET` | `EncoderOptions.stream_offset` |
| Base64 Mode | Yes | `BROTLI_PARAM_BASE64_MODE` | `EncoderOptions.base64_mode` |
| Max Base64 Regions | Yes | `BROTLI_PARAM_MAX_BASE64_REGIONS` | `EncoderOptions.max_base64_regions` |
| Disable Ring Buffer Reallocation | Yes | `BROTLI_DECODER_PARAM_DISABLE_RING_BUFFER_REALLOCATION` | `DecoderOptions.disable_ring_buffer_reallocation` |
| Decoder Large Window | Yes | `BROTLI_DECODER_PARAM_LARGE_WINDOW` | `DecoderOptions.large_window` |
| Streaming Encode | Yes | `BrotliEncoderCompressStream` | `Encoder.compressStream` |
| Streaming Decode | Yes | `BrotliDecoderDecompressStream` | `Decoder.decompressStream` |
| One-shot Compress | Yes | `BrotliEncoderCompress` | `brotli.compress` / `oneshot.compress` |
| One-shot Decompress | Yes | `BrotliDecoderDecompress` | `brotli.decompress` / `oneshot.decompress` |
| Shared Dictionary | Yes | `BrotliSharedDictionary*` | `SharedDictionary` |
| Prepared Dictionary | Yes | `BrotliEncoderPrepareDictionary` | `PreparedDictionary` |
| Custom Allocator | Yes | `brotli_alloc_func` / `brotli_free_func` | All `init` functions accept `std.mem.Allocator` |
| Metadata Blocks | Yes | `BROTLI_OPERATION_EMIT_METADATA` | `EncoderOperation.emit_metadata` |
| Version Query | Yes | `BrotliEncoderVersion` / `BrotliDecoderVersion` | `brotli.version()` |

## Usage

See the [examples/](examples/) directory for complete, runnable programs.

### Streaming Example

```zig
var enc = try brotli.encoder.Encoder.init(allocator, .{ .quality = 6 });
defer enc.deinit();

var output: [4096]u8 = undefined;

// Feed data in chunks
const result = try enc.compressStream(.process, chunk, &output);
// ... repeat with more chunks ...

// Finalize
const final = try enc.compressStream(.finish, &.{}, &output);
```

### Custom Allocator Example

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();

const compressed = try brotli.compress(arena.allocator(), data);
const decompressed = try brotli.decompress(arena.allocator(), compressed);
```

## Building & Testing

```bash
zig build            # Build library
zig build test       # Run unit tests
zig build examples   # Build all examples
```

### Build Options

| Option | Default | Description |
|---|---|---|
| `-Dportable` | `false` | Build with `BROTLI_BUILD_PORTABLE=1` |
| `-Dshared` | `false` | Build Brotli as a shared library instead of static |

## API Overview

| Module | Description |
|---|---|
| `brotli` | Public root module with convenience functions |
| `brotli.common.types` | Shared enums, error sets, version helpers |
| `brotli.common.allocator` | Zig `std.mem.Allocator` to Brotli C allocator bridge |
| `brotli.common.dictionary` | `SharedDictionary` and `PreparedDictionary` wrappers |
| `brotli.encoder.Encoder` | Streaming encoder with full parameter coverage |
| `brotli.encoder.EncoderOptions` | Typed encoder parameter struct |
| `brotli.decoder.Decoder` | Streaming decoder with full parameter coverage |
| `brotli.decoder.DecoderOptions` | Typed decoder parameter struct |
| `brotli.version` | Encoder and decoder version accessors |

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT - see [LICENSE](LICENSE).

Original Brotli code: Copyright (c) 2009, 2010, 2013-2016 by the Brotli Authors (Google).

Zig bindings: Copyright (c) 2026 Muhammad Fiaz.

## Author

**Muhammad Fiaz** - Zig bindings, build system, and API design

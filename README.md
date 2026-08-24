<div align="center">

# brotli.zig

<a href="https://muhammad-fiaz.github.io/brotli.zig/"><img src="https://img.shields.io/badge/docs-muhammad--fiaz.github.io-blue" alt="Documentation"></a>
<a href="https://ziglang.org/"><img src="https://img.shields.io/badge/Zig-0.16.0-orange.svg?logo=zig" alt="Zig Version"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig"><img src="https://img.shields.io/github/stars/muhammad-fiaz/brotli.zig" alt="GitHub stars"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/issues"><img src="https://img.shields.io/github/issues/muhammad-fiaz/brotli.zig" alt="GitHub issues"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/pulls"><img src="https://img.shields.io/github/issues-pr/muhammad-fiaz/brotli.zig" alt="GitHub pull requests"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig"><img src="https://img.shields.io/github/last-commit/muhammad-fiaz/brotli.zig" alt="GitHub last commit"></a>
<a href="https://github.com/muhammad-fiaz/brotli.zig/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></a>
<img src="https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macos-blue" alt="Supported Platforms">
<a href="https://github.com/muhammad-fiaz/brotli.zig/releases/latest"><img src="https://img.shields.io/github/v/release/muhammad-fiaz/brotli.zig?label=Latest%20Release&style=flat-square" alt="Latest Release"></a>
<a href="https://pay.muhammadfiaz.com"><img src="https://img.shields.io/badge/Sponsor-pay.muhammadfiaz.com-ff69b4?style=flat&logo=heart" alt="Sponsor"></a>
<a href="https://github.com/sponsors/muhammad-fiaz"><img src="https://img.shields.io/badge/Sponsor-GitHub-pink?style=social&logo=github" alt="GitHub Sponsors"></a>

<p><em>Native Zig implementation of the Brotli RFC 7932 compression format.</em></p>

<b><a href="https://muhammad-fiaz.github.io/brotli.zig/">Documentation</a> |
<a href="https://muhammad-fiaz.github.io/brotli.zig/api/">API Reference</a> |
<a href="https://muhammad-fiaz.github.io/brotli.zig/guide/getting-started">Quick Start</a> |
<a href="CONTRIBUTING.md">Contributing</a></b>

</div>

`brotli.zig` is a complete native Zig implementation of the [Brotli](https://www.brotli.org/) compressed-data format (RFC 7932, including Large Window Brotli). No C bindings, no external dependencies. Every byte is Zig.

> [!TIP]
> If you build with brotli.zig, make sure to give it a star.

> [!IMPORTANT]
> **Version 0.0.1 used C bindings** as a wrapper around the reference Brotli C library.
> It is deprecated and should not be used in new projects. Starting with **v0.0.3**,
> `brotli.zig` is a fully native Zig implementation — no C code, no libc, no external
> dependencies. All compression and decompression runs entirely in Zig.

> [!NOTE]
> This implementation is based on **Brotli v1.2.0** as the format specification (RFC 7932), re-designed with Zig idioms and implemented natively.
>
> **Pure Zig — zero C dependencies:** Unlike binding-based approaches, `brotli.zig` implements the Brotli format directly in Zig, including:
> - **Streaming decoder state machine** — window bits (incl. large window), metablock headers, metadata blocks, uncompressed metablocks, partial input/output resumption
> - **Huffman decoding** — code-length tables, two-level explicit tables, simple/tree-select tables
> - **Context modeling** — the full 2048-entry literal context lookup table; the encoder emits second-order context-modeled literals with clustered context maps
> - **LZ77 back-references** with distance ring-buffer shortcuts
> - **Static dictionary** — the complete 122,784-byte RFC 7932 word list; the encoder emits dictionary word references (including uppercase transforms) and both sides accept custom raw dictionaries
> - **Custom dictionaries** — attach shared raw bytes to encoder and decoder for small-payload compression
> - **Native encoder** — hash-chain match finder, Huffman table construction, metablock emission, quality levels 0–11, literal block switching, second-order context modeling with clustered context maps, NPOSTFIX/NDIRECT distance coding, large-window streams up to LGWIN 30, and metadata metablocks
> - **Progress callbacks** — observe streaming compression progress for large files
> - **Parameter API** — all nine `PARAM_*` encoder knobs mirroring the C enumeration

---

<details>
<summary><strong>Features</strong> (click to expand)</summary>

| Feature | Description |
|---------|-------------|
| **One-shot Compression** | `brotli.compress()` for single-call compression with default options |
| **One-shot Decompression** | `brotli.decompress()` for single-call decompression |
| **Compression Levels** | Quality 0–11 via `brotli.compressWithOptions(.{ .quality = ... })` |
| **Reusable Encoder** | `Encoder` for efficient multi-block streaming with `setParameter()` control |
| **Reusable Decoder** | `Decoder` streaming state machine with detailed error codes |
| **Streaming Compression** | `StreamingCompressor` chunked processing with `process`/`flush`/`finish` |
| **Streaming Decompression** | `StreamingDecompressor` chunked processing with `feed`/`take` |
| **Dictionary Compression** | `attachDictionary()` on both encoder and decoder |
| **Built-in Static Dictionary** | Complete RFC 7932 122,784-byte word list + 121 transforms, zero config |
| **Window Sizes** | LGWIN 10â€“24 standard; large-window decode up to 30 |
| **Modes** | Generic, text, and font analysis hints |
| **Large Window** | Optional LGWIN up to 30 encode/decode (incompatible extension) |
| **Metadata Blocks** | Emit side-channel metadata via `emitMetadata()` / `.emit_metadata` |
| **Parameter API** | All nine `PARAM_*` identifiers mirroring `BrotliEncoderSetParameter` |
| **Progress Callbacks** | Optional observer during streaming compression |
| **Preallocated Output** | `decompressInto()` and `maxCompressedSize()` for buffer control |
| **Detailed Errors** | Every decoder failure carries a named `ErrorCode` mirroring C strings |
| **Cross-platform** | Linux, Windows, macOS; x86_64, aarch64, x86 (32-bit) |
| **Zero Dependencies** | Pure Zig implementation — no C libraries, no system dependencies |

</details>

---

<details>
<summary><strong>Prerequisites and Supported Platforms</strong> (click to expand)</summary>

<br>

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Zig** | **0.16.0** (required) | Download from [ziglang.org](https://ziglang.org/download/) |
| **Operating System** | Windows 10+, Linux, macOS | Cross-platform support |

---

## Supported Platforms

`brotli.zig` targets these architectures:

| Platform | x86_64 (64-bit) | aarch64 (ARM64) | x86 (32-bit) |
|----------|-----------------|-----------------|--------------|
| **Linux** | Yes | Yes | Yes |
| **Windows** | Yes | Yes | Yes |
| **macOS** | Yes | Yes (Apple Silicon) | Yes |

### Cross-Compilation

Zig makes cross-compilation easy. Build for any target from any host:

```bash
# Build for Linux ARM64 from Windows
zig build -Dtarget=aarch64-linux

# Build for Windows from Linux
zig build -Dtarget=x86_64-windows

# Build for macOS Apple Silicon from Linux
zig build -Dtarget=aarch64-macos

# Build for 32-bit Windows
zig build -Dtarget=x86-windows
```

</details>

---

## Installation

### Method 1: Zig Fetch (Recommended)

**Latest Release (v0.0.3)**

```bash
zig fetch --save https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/0.0.3.tar.gz
```

### Method 2: Zig Fetch (Main Branch)

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/brotli.zig.git
```

### Method 3: Manual `build.zig.zon` Configuration

```zig
.dependencies = .{
    .brotli = .{
        .url = "https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/0.0.3.tar.gz",
        .hash = "...", // Run `zig fetch --save <url>` to generate the hash.
    },
},
```

### Method 4: Local Source Checkout

```bash
git clone https://github.com/muhammad-fiaz/brotli.zig.git
cd brotli.zig
zig build
```

Path dependency in another project's `build.zig.zon`:

```zig
.dependencies = .{
    .brotli = .{
        .path = "../brotli.zig",
    },
},
```

### Wire into `build.zig`

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});

const brotli_dep = b.dependency("brotli", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("brotli", brotli_dep.module("brotli"));
```

## Quick Start

### One-Liner Compression

```zig
const brotli = @import("brotli");

const compressed = try brotli.compress(allocator, data);
defer allocator.free(compressed);

const decompressed = try brotli.decompress(allocator, compressed);
defer allocator.free(decompressed);
```

### Full Options

```zig
const compressed = try brotli.compressWithOptions(allocator, data, .{
    .quality = 9,          // 0..11
    .lgwin = 22,           // 10..24 window bits
    .mode = .text,         // generic | text | font
    .size_hint = data.len, // improves progress reporting
});
defer allocator.free(compressed);
```

### Reusable Contexts

```zig
var enc = brotli.Encoder.init(allocator, .{ .quality = 11 });
defer enc.deinit();

try enc.compressStream(.process, chunk_a);
try enc.compressStream(.flush, null);
try enc.compressStream(.finish, null);
// drain enc.out.items[enc.out_pos..]
```

### Simplified API Aliases

```zig
// Compression
const compressed = try brotli.compress(allocator, data);
const tuned = try brotli.compressWithOptions(allocator, data, .{ .quality = 9 });
const bound = brotli.maxCompressedSize(data.len);

// Decompression
const out = try brotli.decompress(allocator, compressed);
var dst: [1024]u8 = undefined;
const n = try brotli.decompressInto(allocator, compressed, &dst);

// Dictionaries
_ = enc.attachDictionary(dict_bytes);
_ = dec.attachDictionary(dict_bytes);

// Progress
enc.setProgress(myCallback, &my_ctx);

// Version
const ver = brotli.versionNumber();
const str = brotli.versionString();
```

### Streaming

```zig
// Compression
var sc = brotli.StreamingCompressor.init(allocator, .{ .quality = 9 });
defer sc.deinit();
const piece = try sc.process(chunk);   // returns owned slice
const tail = try sc.finish();          // final block

// Decompression
var sd = brotli.StreamingDecompressor.init(allocator, .{});
defer sd.deinit();
sd.feed(chunk);
var buf: [4096]u8 = undefined;
const n = try sd.take(&buf);
```

### Dictionary Compression

```zig
// Attach identical bytes to both sides BEFORE use.
if (!enc.attachDictionary(dict_bytes)) return error.InvalidDictionary;
if (!dec.attachDictionary(dict_bytes)) return error.InvalidDictionary;

// Now streams reference the corpus compactly:
const tiny = try brotli.compress(allocator, overlapping_input);
defer allocator.free(tiny); // only decodable with the same dict attached
```

The built-in RFC 7932 static dictionary works automatically on both sides.


## API Reference

### Top-Level Functions

| Function | Description |
|---|---|
| `brotli.compress(alloc, src)` | One-shot compression (quality 11) |
| `brotli.decompress(alloc, src)` | One-shot decompression |
| `brotli.compressWithOptions(alloc, src, opts)` | Compress with `CompressionOptions` |
| `brotli.decompressWithOptions(alloc, src, opts)` | Decompress with `DecoderOptions` |
| `brotli.decompressInto(dst, src)` | Decompress into preallocated buffer |
| `brotli.maxCompressedSize(src_size)` | Maximum compressed size for allocation |
| `brotli.versionString()` / `versionNumber()` | Library version |

### Types

| Type | Description |
|---|---|
| `Encoder` | Streaming encoder: `init(alloc, opts)`, `setParameter(id, val)`, `attachDictionary()`, `setProgress()`, `compressStream(op, in)`, `takeOutput()`, `isFinished()` |
| `Decoder` | Streaming decoder: `init(alloc, opts)`, `attachDictionary()`, `decompressStream(&in,&out,&total)`, `errorCode().name()` |
| `StreamingCompressor` | Chunk facade: `init(alloc, opts)`, `process(chunk)`, `flush()`, `finish()`, `setProgress()`, `attachDictionary()` |
| `StreamingDecompressor` | Chunk facade: `init(alloc, opts)`, `feed(chunk)`, `take(out)`, `isFinished()`, `totalOut()` |
| `CompressionOptions` | quality, lgwin, mode, lgblock, size_hint, large_window, npostfix, ndirect, progress, progress_ctx |
| `DecoderOptions` | `large_window: bool` |
| `ErrorCode` | Named decoder errors mirroring `BrotliDecoderErrorStr` |
| `MetadataCallbacks` | Decoder metadata-block observers |

### Parameter Identifiers

`PARAM_MODE`, `PARAM_QUALITY`, `PARAM_LGWIN`, `PARAM_LGBLOCK`,
`PARAM_DISABLE_LITERAL_CONTEXT_MODELING`, `PARAM_SIZE_HINT`,
`PARAM_LARGE_WINDOW`, `PARAM_NPOSTFIX`, `PARAM_NDIRECT` — pass to
`Encoder.setParameter(id, value)`.

### Namespaces

| Namespace | Description |
|---|---|
| `brotli.constants` | Format limits: alphabet sizes, window bounds, distance caps |
| `brotli.Dictionary` | Embedded RFC 7932 static dictionary resource |
| `brotli.huffman` / `bit_writer` / `BitReader` | Low-level primitives (advanced use) |

## Examples

The `examples/` directory contains runnable examples:

| Example | File | Description |
|---------|------|-------------|
| `compress_file` | `examples/compress_file.zig` | One-shot compression across quality levels with round-trip verification |
| `streaming_compression` | `examples/streaming_compression.zig` | 4 MiB chunked streaming with progress callback |
| `decompress_file` | `examples/decompress_file.zig` | Basic decompression |
| `streaming_decompression` | `examples/streaming_decompression.zig` | Chunked decompression |
| `dictionary_compression` | `examples/dictionary_compression.zig` | Shared-dictionary round trip (plain decode fails without it!) |
| `reusable_context` | `examples/reusable_context.zig` | Multiple streams on one context |
| `error_handling` | `examples/error_handling.zig` | Corruption, truncation, and error diagnostics |
| `format_introspection` | `examples/format_introspection.zig` | Version, limits, and constants |
| `bit_level` | `examples/bit_level.zig` | Low-level bit reader/writer primitives |

To run any example:

```bash
zig build run-compress_file
zig build run-streaming_compression
zig build run-dictionary_compression
zig build run-all-examples   # everything at once
```

## Validation Matrix

Validate host functionality and cross-target compatibility:

```bash
# Host runtime validation
zig build test --summary all
zig build run-all-examples

# Cross-target library compile validation
zig build -Dtarget=aarch64-linux
zig build -Dtarget=x86_64-windows
zig build -Dtarget=aarch64-macos
zig build -Dtarget=x86-windows
```

## Building & Testing

```bash
zig build                    # Build library
zig build test               # Run all tests
zig build test --summary all # With summary
zig build run-all-examples   # Run all examples
zig build fuzz               # Decoder robustness fuzzer
zig build docs               # Generate API documentation
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `zig build test --summary all`
5. Ensure formatting passes: `zig fmt --check src/`
6. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

**Muhammad Fiaz** (https://github.com/muhammad-fiaz)

---
title: Getting Started
description: Get up and running with brotli.zig in minutes.
---

# Getting Started

brotli.zig is a complete native Zig implementation of [Brotli](https://www.brotli.org/) compression (RFC 7932). No C bindings, no external dependencies â€” just Zig.

::: warning Version Requirement
This library targets **Zig 0.17.0** (required). Download from [ziglang.org](https://ziglang.org/download/).

| Zig Version | Status |
|---|---|
| 0.17.0 | Supported — required for this library |
:::

## Quick Start

Add brotli.zig to your `build.zig.zon`:

```zig
.brotli = .{
    .url = "https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/v0.0.4.tar.gz",
    .hash = "...",  // use zig fetch --save to get the hash
},
```

Then in your `build.zig`:

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});
const brotli_dep = b.dependency("brotli", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("brotli", brotli_dep.module("brotli"));
```

## Basic Usage

### One-Shot Compression

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "Hello, brotli.zig! This text will be compressed.";

    // Compress with default options (quality 11, window 22).
    const compressed = try brotli.compress(allocator, original);
    defer allocator.free(compressed);

    // Decompress.
    const decompressed = try brotli.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Original: {s}\n", .{original});
    std.debug.print("Compressed: {d} bytes\n", .{compressed.len});
    std.debug.print("Decompressed: {s}\n", .{decompressed});
}
```

### With Quality Level

Quality is a plain `u32` in range 0â€“11:

```zig
// Fastest
const fast = try brotli.compressWithOptions(allocator, data, .{ .quality = 1 });

// Best ratio
const best = try brotli.compressWithOptions(allocator, data, .{ .quality = 11 });

// Balanced
const balanced = try brotli.compressWithOptions(allocator, data, .{ .quality = 9 });
```

### With Options

```zig
const opts = brotli.CompressionOptions{
    .quality = 9,
    .lgWin = 22,
    .mode = .text,
    .sizeHint = data.len,
};
const compressed = try brotli.compressWithOptions(allocator, data, opts);
defer allocator.free(compressed);
```

## Reusable Contexts

For repeated operations with the same settings:

```zig
var enc = brotli.Encoder.init(allocator, .{ .quality = 9 });
defer enc.deinit();

var dec = brotli.Decoder.init(allocator, .{});
defer dec.deinit();

// Compress multiple buffers through one encoder.
try enc.compressStream(.process, data1);
try enc.compressStream(.finish, null);
// drain enc.out.items[enc.out_pos..]

// Decompress through one decoder.
var in: []const u8 = compressed;
var out_buf: [65536]u8 = undefined;
var avail: []u8 = &out_buf;
var total: u64 = 0;
_ = try dec.decompressStream(&in, &avail, &total);
```

Or use the chunk facades:

```zig
var sc = brotli.StreamingCompressor.init(allocator, .{});
defer sc.deinit();
var sd = brotli.StreamingDecompressor.init(allocator, .{});
defer sd.deinit();
```

## Acknowledgements

`brotli.zig` is a native Zig implementation of the Brotli format and codec, built entirely from scratch in Zig.

The [Brotli project](https://github.com/google/brotli) is used as a reference for the Brotli format, codec behavior, compatibility, and interoperability verification.

This project does not depend on the upstream implementation.

## What's Next

- [Installation](/guide/installation) — Detailed setup instructions
- [Compression](/guide/compression) — All compression options
- [Decompression](/guide/decompression) — Decompression details
- [Streaming](/guide/streaming) — Chunk-based processing
- [Dictionaries](/guide/dictionaries) — Dictionary compression

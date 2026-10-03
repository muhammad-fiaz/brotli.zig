---
title: DecompressionOptions
description: Comprehensive configuration and resource limits for the native Brotli decoder.
---

# DecompressionOptions

`DecompressionOptions` configures the native Brotli decoder, enabling extensions such as Large Window decoding, custom dictionary back-references, and explicit memory limits.

Defined in `src/decompress/decode.zig` and re-exported as `brotli.DecompressionOptions` (and `brotli.DecoderOptions`).

## Struct Definition

```zig
pub const DecompressionOptions = struct {
    /// Enable "Large Window Brotli" (window up to 30 bits).
    largeWindow: bool = false,

    /// When true, ring buffer grows in small incremental steps (saves RAM for small streams).
    cannyRingbufferAllocation: bool = true,

    /// Optional raw custom dictionary data matching the compression side.
    customDictionary: ?[]const u8 = null,

    /// Safety limit on ring buffer size in bytes (0 = no limit).
    ringBufferSizeLimit: usize = 0,

    /// Safety limit on maximum decompressed output size in bytes (null = no limit).
    maxOutputSize: ?usize = null,

    /// Callbacks for observing metadata metablocks.
    metadataCallbacks: ?MetadataCallbacks = null,
};
```

## Field Reference

| Field | Type | Default | Description |
|---|---|---|---|
| `largeWindow` | `bool` | `false` | Accepts Large Window Brotli streams (LGWIN up to 30 bits, 1 GiB window). |
| `cannyRingbufferAllocation` | `bool` | `true` | Incrementally sizes ring buffers to reduce RAM usage for small streams. |
| `customDictionary` | `?[]const u8` | `null` | Pre-attached raw dictionary matching the dictionary used during compression. |
| `ringBufferSizeLimit` | `usize` | `0` | Upper limit on allocated ring buffer capacity. If a stream demands a larger window, decoding aborts with `error.ResourceLimitExceeded`. `0` means unbounded. |
| `maxOutputSize` | `?usize` | `null` | Maximum allowed uncompressed byte count. Protects against zip-bomb and decompression amplification attacks. |
| `metadataCallbacks` | `?MetadataCallbacks` | `null` | Optional hooks fired when encountering RFC 7932 section 9.2 metadata blocks. |

## Metadata Callbacks (`MetadataCallbacks`)

```zig
pub const MetadataCallbacks = struct {
    ctx: ?*anyopaque = null,
    start: ?*const fn (ctx: ?*anyopaque, size: usize) void = null,
    chunk: ?*const fn (ctx: ?*anyopaque, data: []const u8) void = null,
};
```

Metadata blocks carry arbitrary application-level annotations and are ignored by standard decoders:

```zig
fn onMetaStart(ctx: ?*anyopaque, size: usize) void {
    _ = ctx;
    std.debug.print("Incoming metadata block of {d} bytes\n", .{size});
}

fn onMetaChunk(ctx: ?*anyopaque, data: []const u8) void {
    _ = ctx;
    std.debug.print("Metadata payload chunk: {d} bytes\n", .{data.len});
}

const opts = brotli.DecompressionOptions{
    .metadataCallbacks = .{
        .start = onMetaStart,
        .chunk = onMetaChunk,
    },
};
```

## Security & Denial of Service Protection Example

When decompressing untrusted inputs from untrusted clients, always configure resource limits:

```zig
const untrusted_options = brotli.DecompressionOptions{
    .largeWindow = false,                       // Reject large-window memory demands
    .ringBufferSizeLimit = 16 * 1024 * 1024,    // Max 16 MiB window buffer
    .maxOutputSize = 64 * 1024 * 1024,          // Max 64 MiB total uncompressed data
};

const result = brotli.decompressWithOptions(allocator, untrusted_data, untrusted_options) catch |err| switch (err) {
    error.ResourceLimitExceeded, error.OutputLimitExceeded => {
        std.debug.print("Payload rejected: exceeded security limits\n", []);
        return;
    },
    else => return err,
};
defer allocator.free(result);
```

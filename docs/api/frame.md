---
title: Format Introspection & Bitstream
description: Stream structure, bounds calculation, BitReader/bit_writer, and format introspection in brotli.zig.
---

# Format Introspection & Bitstream

Unlike archive container formats (such as ZIP or TAR), standard Brotli streams (RFC 7932) do not feature an uncompressed length header or magic numbers. The stream consists of:

1. **Stream Header**: 1 to 4 bits specifying the sliding window size (`WBITS`), followed by an optional large-window bit.
2. **Sequence of Meta-Blocks**: Each meta-block is preceded by a variable-length header specifying uncompressed length (`MLEN`), compression mode (uncompressed, empty, or Huffman compressed), and block tree structures.
3. **Stream Terminator**: An empty meta-block marked with `ISLAST = 1` and `ISLASTEMPTY = 1`.

## Size Bounds & Verification

### `maxCompressedSize`

```zig
pub fn maxCompressedSize(input_size: usize) usize
```

Calculates the maximum memory required to hold the compressed bitstream for any arbitrary input size (mirroring `BrotliEncoderMaxCompressedSize`). Even if the data is completely incompressible, the compressed output is guaranteed to fit within `maxCompressedSize(input_size)`.

### Buffer Validation with `decompressInto`

```zig
pub fn decompressInto(
    allocator: std.mem.Allocator,
    input: []const u8,
    output: []u8,
) !usize
```

Decompresses directly into a fixed slice without dynamic heap reallocation for output data. If the stream attempts to write beyond `output.len`, decompression fails with `error.OutputTooSmall` or `error.ResourceLimitExceeded`.

```zig
var buffer: [65536]u8 = undefined;
const bytes_written = try brotli.decompressInto(allocator, compressed_slice, &buffer);
const original_data = buffer[0..bytes_written];
```

## Low-Level Bitstream Utilities

For advanced applications requiring direct access to the Brotli bit-level protocol, `brotli.zig` re-exports the `BitReader` and `bit_writer` primitives:

### `BitReader` (`brotli.BitReader`)

Defined in `src/bitstream/bit_reader.zig`:

```zig
pub const BitReader = struct {
    val: u64,           // 64-bit bit reservoir
    bit_pos: u6,        // Valid bits in reservoir (0..64)
    pos: usize,         // Byte position in input slice
    // ...

    pub fn init(src: []const u8) BitReader
    pub fn fill(self: *BitReader, src: []const u8) void
    pub fn peekBits(self: *const BitReader, n: u5) u64
    pub fn dropBits(self: *BitReader, n: u6) void
    pub fn readBits(self: *BitReader, src: []const u8, n: u5) u32
};
```

### `bit_writer` (`brotli.bit_writer`)

Defined in `src/bitstream/bit_writer.zig`:

```zig
pub fn writeBits(storage: *std.ArrayList(u8), allocator: Allocator, n_bits: usize, bits: u32) !void
pub fn writeBitsPrepare(storage: *std.ArrayList(u8), allocator: Allocator, n_bits: usize) !void
```

## Format Introspection Example

```zig
const brotli = @import("brotli");

// Parse the window bits from the start of a Brotli stream:
var br = brotli.BitReader.init(stream_data);
br.fill(stream_data);

// Inspect the first bit (RFC 7932 window bit encoding)
const wbit_0 = br.readBits(stream_data, 1);
if (wbit_0 == 0) {
    // 16 bits default window
    std.debug.print("Stream window size: 16 bits (64 KiB)\n", .{});
} else {
    const wbits_next = br.readBits(stream_data, 3);
    if (wbits_next != 0) {
        std.debug.print("Stream window bits: {d}\n", .{17 + wbits_next});
    } else {
        const wbits_sub = br.readBits(stream_data, 3);
        std.debug.print("Stream window bits: {d}\n", .{10 + wbits_sub});
    }
}
```

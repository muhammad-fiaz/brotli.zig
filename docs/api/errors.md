---
title: Errors & Diagnostics
description: Canonical error set, detailed RFC 7932 error codes, and decoder diagnostics in brotli.zig.
---

# Errors & Diagnostics

`brotli.zig` provides a two-tiered error system:

1. **Standard Zig Error Set (`brotli.Error`)**: Canonical errors returned across public functions.
2. **Fine-Grained Decoder Diagnostics (`ErrorCode` & `BrotliErrorInfo`)**: Mirroring the C reference library's error codes to pin down the exact byte and RFC 7932 section where bitstream corruption occurred.

## Canonical Public Error Set (`brotli.Error`)

Defined in `src/brotli.zig`:

| Error | Meaning |
|---|---|
| `CorruptStream` | Bitstream payload does not conform to RFC 7932 |
| `TruncatedInput` | Stream ended unexpectedly before completing the terminating meta-block |
| `InvalidHeader` | Malformed stream window bits, nibbles, or padding |
| `InvalidMetaBlock` | Unparseable meta-block header or reserved field set |
| `InvalidHuffmanTree` | Inconsistent or oversubscribed Huffman code lengths |
| `InvalidCommand` | Illegal insert-and-copy command code |
| `InvalidDistance` | Backward reference points beyond the valid ring-buffer window |
| `InvalidDictionaryReference` | Transform or dictionary index is out of bounds |
| `ResourceLimitExceeded` | Ring buffer size exceeds `ringBufferSizeLimit` |
| `OutputLimitExceeded` | Decompressed payload exceeds `maxOutputSize` |
| `OutOfMemory` | Memory allocator failed to allocate workspace or output |
| `InvalidParameter` | An invalid configuration parameter or option was supplied |
| `InvalidStreamingState` | Decoder or encoder operation attempted in an inconsistent state |
| `NeedsMoreInput` | Streaming input exhausted before stream completed |
| `NeedsMoreOutput` | Destination buffer filled while uncompressed data remains |
| `BrotliCompressionError` | Encoder failure during compression |
| `BrotliDecompressionError` | Decoder failure during decompression |
| `BrotliStreamError` | Generic streaming I/O pipeline failure |

## Detailed Diagnostic Codes (`ErrorCode`)

The decoder tracks exact failure modes with `ErrorCode`, mirroring the upstream `BrotliDecoderErrorCode` enumeration:

```zig
pub const ErrorCode = enum(i8) {
    no_error = 0,
    success = 1,
    needs_more_input = 2,
    needs_more_output = 3,

    // Stream format errors (< 0)
    format_exuberant_nibble = -1,
    format_reserved = -2,
    format_exuberant_meta_nibble = -3,
    format_simple_huffman_alphabet = -4,
    format_simple_huffman_same = -5,
    format_cl_space = -6,
    format_huffman_space = -7,
    format_context_map_repeat = -8,
    format_block_length_1 = -9,
    format_block_length_2 = -10,
    format_transform = -11,
    format_dictionary = -12,
    format_window_bits = -13,
    format_padding_1 = -14,
    format_padding_2 = -15,
    format_distance = -16,
    format_block_switch = -17,
    error_compound_dictionary = -18,
    error_dictionary_not_set = -19,
    error_invalid_arguments = -20,

    // Allocation errors
    alloc_context_modes = -21,
    alloc_tree_groups = -22,
    alloc_context_map = -25,
    alloc_ring_buffer_1 = -26,
    alloc_ring_buffer_2 = -27,
    alloc_block_type_trees = -30,

    unreachable_state = -31,
    resource_limit = -32,
};
```

### Methods on `ErrorCode`

- `code.isError() bool`: Returns `true` if `code < 0`.
- `code.name() []const u8`: Returns the canonical C string identifier (e.g. `"ERROR_FORMAT_PADDING_1"`).
- `code.toError() anyerror`: Converts the code into the corresponding Zig `brotli.Error`.

## `BrotliErrorInfo`

`BrotliErrorInfo` is a diagnostic wrapper exported by `src/brotli.zig`:

```zig
pub const BrotliErrorInfo = struct {
    code: ErrorCode,

    pub fn name(self: BrotliErrorInfo) []const u8
    pub fn isError(self: BrotliErrorInfo) bool
    pub fn toError(self: BrotliErrorInfo) Error
};
```

## Example: Diagnosing Stream Failures

```zig
var dec = brotli.Decompressor.init(allocator, .{});
defer dec.deinit();

var in_slice: []const u8 = corrupted_stream;
var out_buf: [4096]u8 = undefined;
var avail_out: []u8 = &out_buf;

const result = dec.decompressStream(&in_slice, &avail_out, null);
if (result == .err) {
    const code = dec.errorCode();
    const info = brotli.BrotliErrorInfo{ .code = code };

    std.debug.print("Decompression failed with: {s} (ID: {d})\n", .{
        info.name(),
        @intFromEnum(code),
    });
    return info.toError();
}
```

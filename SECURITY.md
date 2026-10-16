# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.0.5   | :white_check_mark: |
| 0.0.4   | :x:                |
| < 0.0.4 | :x:                |

## Known issues in earlier releases

Releases before `0.0.5` could decode incorrectly when a compressed stream was
supplied in small pieces: the decoder did not always resume at the stage it
had stopped at, so literals, Huffman tables and distances could be read from
the wrong bit offset. Such input could yield corrupted output instead of an
error. `0.0.5` fixes this and adds regression coverage that decodes streams
from an independent implementation across every input and output chunk size.

Releases before `0.0.5` could also produce streams that a conforming decoder
rejects when the large-window extension is combined with a non-zero
`npostfix`. The encoder advertised a smaller distance alphabet than a decoder
derives from the stream header, which shifted the simple-tree symbol width and
desynchronised the bit stream. Callers that pass `largeWindow = true` together
with `nPostfix = 3` and a non-zero `nDirect` should upgrade to `0.0.5`.

Releases before `0.0.5` could abort while compressing highly repetitive input
larger than one metablock. The match finder capped a candidate match at the end
of the input buffer rather than the end of the current metablock, so a command
could describe bytes beyond its own block; serializing that block then read
past the end of the block slice and trapped with an out-of-bounds panic.
Reproduction: compress any input above the metablock size in which a single
match can span the boundary, for example a payload of the form
`"ABCD" * n` with `n` large enough to exceed the block size.

Applications that accept untrusted compressed data, or compress untrusted or
generated input, should upgrade to `0.0.5` or later.

## Reporting a Vulnerability

If you discover a security vulnerability in `brotli.zig`, please report it responsibly.

**Please do NOT open a public GitHub issue for security vulnerabilities.**

Instead:

1. Email **contact@muhammadfiaz.com** with details, or
2. Use [GitHub private vulnerability reporting](https://github.com/muhammad-fiaz/brotli.zig/security/advisories/new)

Include:
- A description of the vulnerability
- Steps to reproduce or a proof of concept
- The affected version(s)
- Any potential impact you have identified

You will receive an acknowledgement within **72 hours**. We aim to release a
fix within **30 days** depending on severity, and will publish a security
advisory once a patch is available.

## Scope

`brotli.zig` decompresses untrusted input by design. The following guarantees apply:

- Malformed, truncated, or hostile compressed data must never cause out-of-bounds
  reads/writes, undefined behavior, or hangs - only a returned `brotli.Error`
  (e.g., `error.CorruptStream`, `error.TruncatedInput`, `error.InvalidHeader`) or
  a failure code via `ErrorCode`.
- Decompression validates stream header window bits (including Large Window Brotli bounds),
  meta-block headers (nibbles, reserved bits, empty meta-blocks), Huffman tree constraints
  (simple and complex Huffman tables, code length sums, context map repeats), backward
  reference distances against the declared window and ring buffer limits, and dictionary
  word indices and transforms.
- Explicit resource limit options (`maxOutputSize` and `ringBufferSizeLimit`) protect
  against decompression amplification ("zip bomb") attacks.
- Allocation failures propagate cleanly as `error.OutOfMemory`.
- **Zero Hidden Global State**: There is no mutable global or static state anywhere in
  `brotli.zig`. Every function requires explicit allocator injection (`std.mem.Allocator`).
- **Thread Safety**: All one-shot functions and independent context instances
  (`Compressor`, `Decompressor`, `StreamingCompressor`, `StreamingDecompressor`) are
  fully thread-safe and can be executed concurrently across threads without synchronization.

Out of scope: misuse of the API (e.g., passing slices with invalid lifetimes) and attacks
on the Zig standard library or operating system itself.

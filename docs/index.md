---
layout: home
title: brotli.zig
titleTemplate: Brotli Compression in Pure Zig

hero:
  name: brotli.zig
  text: Native Zig Brotli Codec
  tagline: "A complete, from-scratch Zig implementation of Brotli (RFC 7932). No C bindings, no dependencies. One-shot and streaming compression and decompression, custom dictionaries, progress callbacks, and full encoder parameter control for Zig 0.17.0+."
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: API Reference
      link: /api/
    - theme: alt
      text: GitHub
      link: https://github.com/muhammad-fiaz/brotli.zig

features:
  - title: Pure Zig Implementation
    details: "Complete native Zig implementation of RFC 7932 Brotli. No C bindings, no external dependencies. Every byte is Zig."
  - title: One-Shot & Streaming
    details: "brotli.compress/decompress for one-call usage; StreamingCompressor and StreamingDecompressor for chunk-based processing with flush control."
  - title: Quality 0-11 + Full Control
    details: "Quality levels 0-11, window bits 10-24, modes, size hints, and all nine encoder parameters via compressWithOptions or setParameter."
  - title: Custom Dictionaries
    details: "Attach shared dictionary bytes to the encoder and decoder. Compress small payloads against a shared corpus with real back-references."
  - title: Progress Callbacks
    details: "Optional progress observer fires during streaming compression - ideal for progress bars on large files."
  - title: Cross-Platform
    details: "Works on Linux, Windows, and macOS. Supports 32-bit and 64-bit targets including aarch64."
---

## Installation

Add `brotli.zig` to your project using `zig fetch`:

### For Zig 0.17.0+ (Latest Release v0.0.4)

```bash
zig fetch --save https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/v0.0.4.tar.gz
```

### For Latest Development (Main Branch)

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/brotli.zig.git
```

### For Zig 0.16.0 Compatibility (v0.0.3)

```bash
zig fetch --save https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/v0.0.3.tar.gz
```

## Acknowledgements

`brotli.zig` is a native Zig implementation of the Brotli format and codec, built entirely from scratch in Zig.

The [Brotli project](https://github.com/google/brotli) is used as a reference for the Brotli format, codec behavior, compatibility, and interoperability verification.

This project does not depend on the upstream implementation.
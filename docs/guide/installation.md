---
title: Installation
description: How to install and set up brotli.zig in your Zig project.
---

# Installation

## Requirements

- **Zig 0.17.0** (required) - download from [ziglang.org](https://ziglang.org/download/)
- No external dependencies required - pure Zig implementation
- Supported OS: Windows 10+, Linux, macOS
- Supported architectures: x86_64, aarch64, x86

::: info Version Compatibility
This library (`v0.0.4+`) requires **Zig 0.17.0** as declared in `build.zig.zon` (`minimum_zig_version = "0.17.0"`). For **Zig 0.16.0** support, install release `v0.0.3` (see [Method 1](#method-1-zig-fetch-recommended--latest-release) below).
:::

## Setup

### Method 1: Zig Fetch (Recommended) - Latest Release

```bash
zig fetch --save https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/0.0.4.tar.gz
```

This corresponds to `build.zig.zon` version `0.0.4`:

```zig
.{
    .name = .brotli,
    .version = "0.0.4",
    .minimum_zig_version = "0.17.0",
    // ...
}
```

For projects using **Zig 0.16.0**, install the `v0.0.3` release:

```bash
zig fetch --save https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/0.0.3.tar.gz
```

### Method 2: Zig Fetch (Main Branch)

Use the latest development version from the `main` branch:

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/brotli.zig.git
```

### Method 3: Manual `build.zig.zon` Configuration

Add the dependency to your `build.zig.zon`:

```zig
.dependencies = .{
    .brotli = .{
        .url = "https://github.com/muhammad-fiaz/brotli.zig/archive/refs/tags/0.0.4.tar.gz",
        .hash = "...", // Run `zig fetch --save <url>` to generate the hash.
    },
},
```

### Method 4: Local Source Checkout

Clone the repository locally:

```bash
git clone https://github.com/muhammad-fiaz/brotli.zig.git
cd brotli.zig
zig build
```

To use a local checkout from another project, add a path dependency to your `build.zig.zon`:

```zig
.dependencies = .{
    .brotli = .{
        .path = "../brotli.zig",
    },
},
```

### Wire into `build.zig`

After adding the dependency, import the module in your `build.zig`:

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});

const brotli_dep = b.dependency("brotli", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("brotli", brotli_dep.module("brotli"));
```

### Use in your code

```zig
const brotli = @import("brotli");

// You're ready to go!
const compressed = try brotli.compress(allocator, data);
defer allocator.free(compressed);

const decompressed = try brotli.decompress(allocator, compressed);
defer allocator.free(decompressed);
```

## Verify Installation

```bash
zig build                    # Build library
zig build test --summary all # Run all tests
zig build run-all-examples   # Run all 11 examples
```

If all tests pass, brotli.zig is properly installed.

## Cross-Compilation

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

# Run tests with emulation for cross targets
zig build test -Dtarget=aarch64-linux --summary all -fqemu
```

Validated targets:

| Platform | x86_64 (64-bit) | aarch64 (ARM64) | x86 (32-bit) |
|----------|-----------------|-----------------|--------------|
| **Linux** | Yes | Yes (via QEMU) | Yes |
| **Windows** | Yes | Yes | Yes |
| **macOS** | Yes (via aarch64 runner) | Yes (Apple Silicon) | No |

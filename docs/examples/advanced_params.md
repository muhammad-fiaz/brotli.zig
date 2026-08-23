---
title: Advanced Parameters
description: Quality, window, mode, and parameter identifiers.
---

# Advanced Parameters

All encoder knobs live in `CompressionOptions`:

```zig
const compressed = try brotli.compressWithOptions(allocator, data, .{
    .quality = 9,          // 0..11
    .lgwin = 22,           // 10..24 window bits
    .mode = .text,         // generic | text | font
    .size_hint = data.len, // improves progress reporting
});
```

Instance-style control via `Encoder.setParameter` with `PARAM_*` ids:

```zig
_ = enc.setParameter(brotli.PARAM_QUALITY, 9);
_ = enc.setParameter(brotli.PARAM_LGWIN, 20);
_ = enc.setParameter(brotli.PARAM_SIZE_HINT, 1 << 20);
```

Unknown ids return `false`.
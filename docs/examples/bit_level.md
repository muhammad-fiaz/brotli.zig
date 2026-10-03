---
title: Bit Level
description: LSB-first bit packing and Huffman code reversal.
---

# Bit Level

`examples/bit_level.zig` - demonstrates the bit-level primitives that
underpin every Brotli header field and Huffman code: LSB-first packing,
field extraction, and Huffman code bit-reversal.

## Client Code

```zig
const std = @import("std");

fn appendBits(acc: *u64, n_bits: *u6, value: u64, count: u6) void {
    acc.* |= (value & ((@as(u64, 1) << count) - 1)) << n_bits.*;
    n_bits.* += count;
}

pub fn main() void {
    var acc: u64 = 0;
    var n: u6 = 0;
    appendBits(&acc, &n, 0b101, 3);
    appendBits(&acc, &n, 0b11011, 5);
    std.debug.print("packed {d} bits -> 0x{X:0>2}\n", .{ n, acc });

    const f1: u64 = acc & 7;
    const f2: u64 = (acc >> 3) & 31;
    std.debug.print("field1=0b{b:0>3} field2=0b{b:0>5}\n", .{ f1, f2 });

    var reversed: u6 = 0;
    const code: u6 = 0b110;
    for (0..3) |i| {
        if ((code >> @intCast(i)) & 1 != 0)
            reversed |= @as(u6, 1) << @intCast(2 - i);
    }
    std.debug.print(
        "code 0b110 reversed for stream order: 0b{b:0>3}\n",
        .{reversed},
    );
}
```

## Output

```text
packed 8 bits -> 0xD5
field1=0b101 field2=0b11011
code 0b110 reversed for stream order: 0b011
```

## Explanation

- Brotli streams are **LSB-first**: the least-significant bit of each
  byte is the first bit consumed by the decoder.
- `appendBits` accumulates `count` bits from `value` into `acc` starting
  at bit position `n_bits`, exactly how the encoder packs header fields.
- Packing `0b101` (3 bits) then `0b11011` (5 bits) yields `0b11011101`
  = `0xD5`; the fields extract back cleanly because the widths are known.
- Huffman codes are stored **most-significant-bit first** within each
  code word even though the stream itself flows LSB-first, so the
  encoder reverses each code before emission. The loop demonstrates
  this reversal on the 3-bit code `0b110` &rarr; `0b011`.

Run it:

```bash
zig build run-bit_level
```

//! UTF-8 heuristics and utilities for encoder context mode selection.
//!
//! Evaluates whether an input buffer has a sufficient proportion of valid UTF-8
//! encoded data to benefit from UTF-8 context modeling.

const std = @import("std");

pub const MIN_UTF8_RATIO: f64 = 0.75;

/// Parses one UTF-8 sequence from `input`.
/// Returns the number of bytes consumed (1..4) and whether it was a valid UTF-8 sequence.
pub fn parseUtf8(input: []const u8) struct { bytes: usize, valid: bool } {
    if (input.len == 0) return .{ .bytes = 0, .valid = false };

    // ASCII byte
    if ((input[0] & 0x80) == 0) {
        return .{ .bytes = 1, .valid = true };
    }

    // 2-byte sequence
    if (input.len >= 2 and
        (input[0] & 0xE0) == 0xC0 and
        (input[1] & 0xC0) == 0x80)
    {
        const cp: u32 = (@as(u32, input[0] & 0x1F) << 6) | (input[1] & 0x3F);
        if (cp > 0x7F) return .{ .bytes = 2, .valid = true };
    }

    // 3-byte sequence
    if (input.len >= 3 and
        (input[0] & 0xF0) == 0xE0 and
        (input[1] & 0xC0) == 0x80 and
        (input[2] & 0xC0) == 0x80)
    {
        const cp: u32 = (@as(u32, input[0] & 0x0F) << 12) |
            (@as(u32, input[1] & 0x3F) << 6) |
            (input[2] & 0x3F);
        // Exclude UTF-16 surrogates (0xD800..0xDFFF)
        if (cp > 0x7FF and (cp < 0xD800 or cp > 0xDFFF)) {
            return .{ .bytes = 3, .valid = true };
        }
    }

    // 4-byte sequence
    if (input.len >= 4 and
        (input[0] & 0xF8) == 0xF0 and
        (input[1] & 0xC0) == 0x80 and
        (input[2] & 0xC0) == 0x80 and
        (input[3] & 0xC0) == 0x80)
    {
        const cp: u32 = (@as(u32, input[0] & 0x07) << 18) |
            (@as(u32, input[1] & 0x3F) << 12) |
            (@as(u32, input[2] & 0x3F) << 6) |
            (input[3] & 0x3F);
        if (cp > 0xFFFF and cp <= 0x10FFFF) {
            return .{ .bytes = 4, .valid = true };
        }
    }

    return .{ .bytes = 1, .valid = false };
}

/// Checks whether at least `min_fraction` of `data` consists of valid UTF-8 sequences.
pub fn isMostlyUTF8(data: []const u8, min_fraction: f64) bool {
    if (data.len == 0) return true;

    // Fast-path: use standard library validation for completely valid UTF-8 slices
    if (std.unicode.utf8ValidateSlice(data)) return true;

    var size_utf8: usize = 0;
    var i: usize = 0;
    while (i < data.len) {
        const res = parseUtf8(data[i..]);
        if (res.valid) {
            size_utf8 += res.bytes;
        }
        i += res.bytes;
    }

    return @as(f64, @floatFromInt(size_utf8)) > min_fraction * @as(f64, @floatFromInt(data.len));
}

test "utf8 heuristics identify text and binary" {
    const text = "Hello, world! This is a test of UTF-8 text with symbols: café, résumé, 🦀.";
    try std.testing.expect(isMostlyUTF8(text, MIN_UTF8_RATIO));

    // Arbitrary binary
    const binary = [_]u8{ 0xFF, 0xFE, 0x80, 0x81, 0x82, 0xC0, 0x00, 0xF5, 0xC1, 0xFF };
    try std.testing.expect(!isMostlyUTF8(&binary, MIN_UTF8_RATIO));

    // Mixed predominantly text
    var mixed: [100]u8 = undefined;
    @memset(mixed[0..80], 'A');
    @memset(mixed[80..100], 0xFF);
    try std.testing.expect(isMostlyUTF8(&mixed, MIN_UTF8_RATIO));
}

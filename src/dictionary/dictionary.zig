//! The RFC 7932 static dictionary. The raw word data (122784 bytes) is
//! embedded; per-length size bits and offsets follow the format tables.

const std = @import("std");

pub const data_size: usize = 122784;

/// Raw dictionary words, back to back; a word of length L starts at
/// `offsets_by_length[L] + L * word_index`.
pub const data: *const [data_size]u8 = @embedFile("dictionary.bin");

/// log2 of the number of words of each length (4..24); 0 means no words.
pub const size_bits_by_length = [32]u8{
    0,  0,  0,  0,  10, 10, 11, 11,
    10, 10, 10, 10, 10, 9,  9,  8,
    7,  7,  8,  7,  7,  6,  6,  5,
    5,  0,  0,  0,  0,  0,  0,  0,
};

/// Byte offset of the first word of each length.
pub const offsets_by_length = [32]u32{
    0,      0,      0,      0,      0,      4096,   9216,   21504,
    35840,  44032,  53248,  63488,  74752,  87040,  93696,  100864,
    104704, 106752, 108928, 113536, 115968, 118528, 119872, 121280,
    122016, 122784, 122784, 122784, 122784, 122784, 122784, 122784,
};

/// Minimum/maximum dictionary word lengths that have words.
pub const min_word_length = 4;
pub const max_word_length = 24;

/// Number of words of the given length (0 when none).
pub fn numWordsByLength(len: u32) u32 {
    const bits = size_bits_by_length[len];
    if (bits == 0) return 0;
    return @as(u32, 1) << @intCast(bits);
}

test "dictionary data has the exact RFC 7932 size" {
    try std.testing.expectEqual(@as(usize, 122784), data.len);
    // First word of length 4 is "time" in the static dictionary.
    try std.testing.expectEqualStrings("time", data[0..4]);
}

test "offsets cover the data exactly" {
    var len: u32 = 0;
    while (len < 25) : (len += 1) {
        const n = numWordsByLength(len);
        if (n > 0) {
            const end = offsets_by_length[len] + n * len;
            try std.testing.expect(end <= data_size);
        }
    }
    try std.testing.expectEqual(@as(u32, 122784), offsets_by_length[25]);
}

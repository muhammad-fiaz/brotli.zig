//! Block-length prefix code range table data.

pub const PrefixCodeRange = struct { offset: u16, nbits: u8 };

pub const prefix_code_ranges: [26]PrefixCodeRange = blk: {
    const nbits_table = [26]u8{
        2, 2, 2, 2, 3, 3,  3,  3,  4,  4,  4, 4, 5, 5, 5, 5,
        6, 6, 7, 8, 9, 10, 11, 12, 13, 24,
    };
    var ranges: [26]PrefixCodeRange = undefined;
    var offset: u32 = 1;
    for (0..26) |i| {
        ranges[i] = .{ .offset = @intCast(offset), .nbits = nbits_table[i] };
        offset += @as(u32, 1) << @intCast(nbits_table[i]);
    }
    break :blk ranges;
};

/// Fast search for the block length prefix code (0..25) matching `len`.
pub inline fn findPrefixCode(len: u32) u8 {
    var code: u32 = if (len >= 177) (if (len >= 753) 20 else 14) else (if (len >= 41) 7 else 0);
    while (code < 25 and len >= prefix_code_ranges[code + 1].offset) : (code += 1) {}
    return @intCast(code);
}

const std = @import("std");

test "block length ranges match the format tables" {
    try std.testing.expectEqual(@as(usize, 26), prefix_code_ranges.len);
    try std.testing.expectEqual(@as(u16, 1), prefix_code_ranges[0].offset);
    try std.testing.expectEqual(@as(u8, 2), prefix_code_ranges[0].nbits);
    try std.testing.expectEqual(@as(u16, 16625), prefix_code_ranges[25].offset);
    try std.testing.expectEqual(@as(u8, 24), prefix_code_ranges[25].nbits);
    var i: usize = 1;
    while (i < prefix_code_ranges.len) : (i += 1) {
        const prev_end = @as(u32, prefix_code_ranges[i - 1].offset) +
            (@as(u32, 1) << @as(u5, @intCast(prefix_code_ranges[i - 1].nbits)));
        try std.testing.expectEqual(prefix_code_ranges[i].offset, @as(u16, @intCast(prev_end)));
    }
}

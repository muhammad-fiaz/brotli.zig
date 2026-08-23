//! Block-length prefix code range table data.

pub const PrefixCodeRange = struct { offset: u16, nbits: u8 };

pub const prefix_code_ranges = [26]PrefixCodeRange{
    .{ .offset = 1, .nbits = 2 },
    .{ .offset = 5, .nbits = 2 },
    .{ .offset = 9, .nbits = 2 },
    .{ .offset = 13, .nbits = 2 },
    .{ .offset = 17, .nbits = 3 },
    .{ .offset = 25, .nbits = 3 },
    .{ .offset = 33, .nbits = 3 },
    .{ .offset = 41, .nbits = 3 },
    .{ .offset = 49, .nbits = 4 },
    .{ .offset = 65, .nbits = 4 },
    .{ .offset = 81, .nbits = 4 },
    .{ .offset = 97, .nbits = 4 },
    .{ .offset = 113, .nbits = 5 },
    .{ .offset = 145, .nbits = 5 },
    .{ .offset = 177, .nbits = 5 },
    .{ .offset = 209, .nbits = 5 },
    .{ .offset = 241, .nbits = 6 },
    .{ .offset = 305, .nbits = 6 },
    .{ .offset = 369, .nbits = 7 },
    .{ .offset = 497, .nbits = 8 },
    .{ .offset = 753, .nbits = 9 },
    .{ .offset = 1265, .nbits = 10 },
    .{ .offset = 2289, .nbits = 11 },
    .{ .offset = 4337, .nbits = 12 },
    .{ .offset = 8433, .nbits = 13 },
    .{ .offset = 16625, .nbits = 24 },
};

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

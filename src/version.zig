const std = @import("std");
const c = @import("c.zig").c;
const types = @import("common/types.zig");

pub const version = struct {
    pub fn encoder() types.Version {
        return types.Version.fromPacked(c.BrotliEncoderVersion());
    }

    pub fn decoder() types.Version {
        return types.Version.fromPacked(c.BrotliDecoderVersion());
    }
};

test "version encoder" {
    const v = version.encoder();
    try std.testing.expect(v.major > 0 or v.minor > 0 or v.patch > 0);
}

test "version decoder" {
    const v = version.decoder();
    try std.testing.expect(v.major > 0 or v.minor > 0 or v.patch > 0);
}

test "version encoder and decoder match" {
    const ev = version.encoder();
    const dv = version.decoder();
    try std.testing.expectEqual(ev.major, dv.major);
    try std.testing.expectEqual(ev.minor, dv.minor);
    try std.testing.expectEqual(ev.patch, dv.patch);
}

test "version packed values are consistent" {
    const enc_packed = c.BrotliEncoderVersion();
    const dec_packed = c.BrotliDecoderVersion();
    try std.testing.expectEqual(enc_packed, dec_packed);
}

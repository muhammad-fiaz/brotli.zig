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

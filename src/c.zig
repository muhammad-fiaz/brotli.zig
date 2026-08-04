const std = @import("std");

pub const c = @cImport({
    @cInclude("brotli/encode.h");
    @cInclude("brotli/decode.h");
    @cInclude("brotli/types.h");
    @cInclude("brotli/shared_dictionary.h");
    @cInclude("brotli/port.h");
});

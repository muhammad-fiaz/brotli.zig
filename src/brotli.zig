const std = @import("std");

pub const common = struct {
    pub const types = @import("common/types.zig");
    pub const allocator = @import("common/allocator.zig");
    pub const dictionary = @import("common/dictionary.zig");
};

pub const encoder = struct {
    pub const Encoder = @import("encoder/encoder.zig").Encoder;
    pub const options = @import("encoder/options.zig");
    pub const oneshot = @import("encoder/oneshot.zig");
    pub const EncoderOptions = options.EncoderOptions;
};

pub const decoder = struct {
    pub const Decoder = @import("decoder/decoder.zig").Decoder;
    pub const options = @import("decoder/options.zig");
    pub const oneshot = @import("decoder/oneshot.zig");
    pub const DecoderOptions = options.DecoderOptions;
};

pub const PreparedDictionary = @import("common/dictionary.zig").PreparedDictionary;
pub const SharedDictionary = @import("common/dictionary.zig").SharedDictionary;
pub const DictionaryType = @import("common/dictionary.zig").DictionaryType;

pub const EncoderMode = common.types.EncoderMode;
pub const EncoderOperation = common.types.EncoderOperation;
pub const EncoderOptions = encoder.EncoderOptions;
pub const DecoderResult = common.types.DecoderResult;
pub const DecoderResultTag = common.types.DecoderResultTag;
pub const DecoderOptions = decoder.DecoderOptions;
pub const DecodeError = common.types.DecodeError;
pub const ErrorCode = common.types.ErrorCode;
pub const StreamResult = common.types.StreamResult;
pub const Version = common.types.Version;

pub const EncoderError = common.types.EncoderError;
pub const DecoderError = common.types.DecoderError;
pub const AllocatorError = common.types.AllocatorError;
pub const DictionaryError = common.types.DictionaryError;

pub fn version() Version {
    return @import("version.zig").version.encoder();
}

pub fn compress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return encoder.oneshot.compress(allocator, input, .{});
}

pub fn compressWithOptions(allocator: std.mem.Allocator, input: []const u8, options: encoder.EncoderOptions) ![]u8 {
    return encoder.oneshot.compress(allocator, input, options);
}

pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return decoder.oneshot.decompress(allocator, input);
}

pub fn decompressWithOptions(allocator: std.mem.Allocator, input: []const u8, options: decoder.DecoderOptions) ![]u8 {
    return decoder.oneshot.decompressWith(allocator, input, options);
}

test {
    _ = @import("common/types.zig");
    _ = @import("common/allocator.zig");
    _ = @import("common/dictionary.zig");
    _ = @import("encoder/encoder.zig");
    _ = @import("encoder/options.zig");
    _ = @import("encoder/oneshot.zig");
    _ = @import("decoder/decoder.zig");
    _ = @import("decoder/options.zig");
    _ = @import("decoder/oneshot.zig");
    _ = @import("version.zig");
}

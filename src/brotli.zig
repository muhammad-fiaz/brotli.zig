const std = @import("std");

pub const common = struct {
    pub const types = @import("common/types.zig");
    pub const allocator = @import("common/allocator.zig");
    pub const dictionary = @import("common/dictionary.zig");
};

pub const encoder = struct {
    pub const Encoder = @import("encoder/encoder.zig").Encoder;
    pub const PreparedDictionary = @import("encoder/encoder.zig").PreparedDictionary;
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

pub const PreparedDictionary = encoder.PreparedDictionary;
pub const SharedDictionary = common.dictionary.SharedDictionary;
pub const DictionaryType = common.types.DictionaryType;

// Encoder enums
pub const EncoderMode = common.types.EncoderMode;
pub const EncoderBase64Mode = common.types.EncoderBase64Mode;
pub const EncoderParameter = common.types.EncoderParameter;
pub const EncoderOperation = common.types.EncoderOperation;
pub const EncoderOptions = encoder.EncoderOptions;

// Decoder enums
pub const DecoderParameter = common.types.DecoderParameter;
pub const DecoderOptions = decoder.DecoderOptions;

// Error types
pub const ErrorCode = common.types.ErrorCode;
pub const DecodeError = common.types.DecodeError;
pub const StreamResult = common.types.StreamResult;
pub const Version = common.types.Version;

// Error sets
pub const EncoderError = common.types.EncoderError;
pub const DecoderError = common.types.DecoderError;
pub const AllocatorError = common.types.AllocatorError;
pub const DictionaryError = common.types.DictionaryError;

// Encoder constants
pub const MIN_WINDOW_BITS = common.types.MIN_WINDOW_BITS;
pub const MAX_WINDOW_BITS = common.types.MAX_WINDOW_BITS;
pub const LARGE_MAX_WINDOW_BITS = common.types.LARGE_MAX_WINDOW_BITS;
pub const MIN_INPUT_BLOCK_BITS = common.types.MIN_INPUT_BLOCK_BITS;
pub const MAX_INPUT_BLOCK_BITS = common.types.MAX_INPUT_BLOCK_BITS;
pub const MIN_QUALITY = common.types.MIN_QUALITY;
pub const MAX_QUALITY = common.types.MAX_QUALITY;
pub const DEFAULT_QUALITY = common.types.DEFAULT_QUALITY;
pub const DEFAULT_WINDOW = common.types.DEFAULT_WINDOW;
pub const DEFAULT_BASE64_MODE = common.types.DEFAULT_BASE64_MODE;
pub const DEFAULT_MAX_BASE64_REGIONS = common.types.DEFAULT_MAX_BASE64_REGIONS;
pub const DEFAULT_MODE = common.types.DEFAULT_MODE;

// Shared dictionary constants
pub const SHARED_MIN_DICTIONARY_WORD_LENGTH = common.types.SHARED_MIN_DICTIONARY_WORD_LENGTH;
pub const SHARED_MAX_DICTIONARY_WORD_LENGTH = common.types.SHARED_MAX_DICTIONARY_WORD_LENGTH;
pub const SHARED_NUM_DICTIONARY_CONTEXTS = common.types.SHARED_NUM_DICTIONARY_CONTEXTS;
pub const SHARED_MAX_COMPOUND_DICTS = common.types.SHARED_MAX_COMPOUND_DICTS;
pub const SHARED_MAX_RAW_DICT_SIZE = common.types.SHARED_MAX_RAW_DICT_SIZE;

// Convenience functions
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

pub fn decompressSimple(encoded: []const u8, decoded: []u8) !struct { success: bool, decoded_size: usize } {
    return decoder.oneshot.decompressSimple(encoded, decoded);
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

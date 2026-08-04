const std = @import("std");
const c = @import("../c.zig").c;

// === Encoder Parameter Enums ===

pub const EncoderMode = enum(c_int) {
    generic = c.BROTLI_MODE_GENERIC,
    text = c.BROTLI_MODE_TEXT,
    font = c.BROTLI_MODE_FONT,
};

pub const EncoderBase64Mode = enum(c_int) {
    disabled = c.BROTLI_BASE64_MODE_DISABLED,
    detection = c.BROTLI_BASE64_MODE_DETECTION,
};

pub const EncoderParameter = enum(c_int) {
    mode = c.BROTLI_PARAM_MODE,
    quality = c.BROTLI_PARAM_QUALITY,
    lgwin = c.BROTLI_PARAM_LGWIN,
    lgblock = c.BROTLI_PARAM_LGBLOCK,
    disable_literal_context_modeling = c.BROTLI_PARAM_DISABLE_LITERAL_CONTEXT_MODELING,
    size_hint = c.BROTLI_PARAM_SIZE_HINT,
    large_window = c.BROTLI_PARAM_LARGE_WINDOW,
    npostfix = c.BROTLI_PARAM_NPOSTFIX,
    ndirect = c.BROTLI_PARAM_NDIRECT,
    stream_offset = c.BROTLI_PARAM_STREAM_OFFSET,
    base64_mode = c.BROTLI_PARAM_BASE64_MODE,
    max_base64_regions = c.BROTLI_PARAM_MAX_BASE64_REGIONS,
};

pub const EncoderOperation = enum(c_int) {
    process = c.BROTLI_OPERATION_PROCESS,
    flush = c.BROTLI_OPERATION_FLUSH,
    finish = c.BROTLI_OPERATION_FINISH,
    emit_metadata = c.BROTLI_OPERATION_EMIT_METADATA,
};

// === Decoder Parameter Enums ===

pub const DecoderParameter = enum(c_int) {
    disable_ring_buffer_reallocation = c.BROTLI_DECODER_PARAM_DISABLE_RING_BUFFER_REALLOCATION,
    large_window = c.BROTLI_DECODER_PARAM_LARGE_WINDOW,
};

// === Error Codes ===

pub const ErrorCode = enum(c_int) {
    no_error = 0,
    success = 1,
    needs_more_input = 2,
    needs_more_output = 3,
    error_format_exuberant_nibble = -1,
    error_format_reserved = -2,
    error_format_exuberant_meta_nibble = -3,
    error_format_simple_huffman_alphabet = -4,
    error_format_simple_huffman_same = -5,
    error_format_cl_space = -6,
    error_format_huffman_space = -7,
    error_format_context_map_repeat = -8,
    error_format_block_length_1 = -9,
    error_format_block_length_2 = -10,
    error_format_transform = -11,
    error_format_dictionary = -12,
    error_format_window_bits = -13,
    error_format_padding_1 = -14,
    error_format_padding_2 = -15,
    error_format_distance = -16,
    error_format_block_switch = -17,
    error_compound_dictionary = -18,
    error_dictionary_not_set = -19,
    error_invalid_arguments = -20,
    error_alloc_context_modes = -21,
    error_alloc_tree_groups = -22,
    error_alloc_context_map = -25,
    error_alloc_ring_buffer_1 = -26,
    error_alloc_ring_buffer_2 = -27,
    error_alloc_block_type_trees = -30,
    error_unreachable = -31,

    pub fn fromNative(code: c_int) ErrorCode {
        inline for (std.meta.fields(ErrorCode)) |field| {
            if (code == field.value) return @enumFromInt(field.value);
        }
        return .error_unreachable;
    }

    pub fn name(self: ErrorCode) []const u8 {
        return switch (self) {
            .no_error => "NO_ERROR",
            .success => "SUCCESS",
            .needs_more_input => "NEEDS_MORE_INPUT",
            .needs_more_output => "NEEDS_MORE_OUTPUT",
            .error_format_exuberant_nibble => "ERROR_FORMAT_EXUBERANT_NIBBLE",
            .error_format_reserved => "ERROR_FORMAT_RESERVED",
            .error_format_exuberant_meta_nibble => "ERROR_FORMAT_EXUBERANT_META_NIBBLE",
            .error_format_simple_huffman_alphabet => "ERROR_FORMAT_SIMPLE_HUFFMAN_ALPHABET",
            .error_format_simple_huffman_same => "ERROR_FORMAT_SIMPLE_HUFFMAN_SAME",
            .error_format_cl_space => "ERROR_FORMAT_CL_SPACE",
            .error_format_huffman_space => "ERROR_FORMAT_HUFFMAN_SPACE",
            .error_format_context_map_repeat => "ERROR_FORMAT_CONTEXT_MAP_REPEAT",
            .error_format_block_length_1 => "ERROR_FORMAT_BLOCK_LENGTH_1",
            .error_format_block_length_2 => "ERROR_FORMAT_BLOCK_LENGTH_2",
            .error_format_transform => "ERROR_FORMAT_TRANSFORM",
            .error_format_dictionary => "ERROR_FORMAT_DICTIONARY",
            .error_format_window_bits => "ERROR_FORMAT_WINDOW_BITS",
            .error_format_padding_1 => "ERROR_FORMAT_PADDING_1",
            .error_format_padding_2 => "ERROR_FORMAT_PADDING_2",
            .error_format_distance => "ERROR_FORMAT_DISTANCE",
            .error_format_block_switch => "ERROR_FORMAT_BLOCK_SWITCH",
            .error_compound_dictionary => "ERROR_COMPOUND_DICTIONARY",
            .error_dictionary_not_set => "ERROR_DICTIONARY_NOT_SET",
            .error_invalid_arguments => "ERROR_INVALID_ARGUMENTS",
            .error_alloc_context_modes => "ERROR_ALLOC_CONTEXT_MODES",
            .error_alloc_tree_groups => "ERROR_ALLOC_TREE_GROUPS",
            .error_alloc_context_map => "ERROR_ALLOC_CONTEXT_MAP",
            .error_alloc_ring_buffer_1 => "ERROR_ALLOC_RING_BUFFER_1",
            .error_alloc_ring_buffer_2 => "ERROR_ALLOC_RING_BUFFER_2",
            .error_alloc_block_type_trees => "ERROR_ALLOC_BLOCK_TYPE_TREES",
            .error_unreachable => "ERROR_UNREACHABLE",
        };
    }
};

// === Decode Error ===

pub const DecodeError = struct {
    code: ErrorCode,
    message: []const u8,

    pub fn fromNative(state: ?*c.BrotliDecoderState) DecodeError {
        const code = ErrorCode.fromNative(c.BrotliDecoderGetErrorCode(state));
        const msg_ptr = c.BrotliDecoderErrorString(@intFromEnum(code));
        const message = std.mem.sliceTo(msg_ptr, 0);
        return .{ .code = code, .message = message };
    }
};

// === Streaming Result ===

pub const StreamResult = struct {
    bytes_consumed: usize,
    bytes_produced: usize,
    has_more_output: bool,
    is_finished: bool,
};

// === Version ===

pub const Version = struct {
    major: u8,
    minor: u8,
    patch: u8,

    pub fn fromPacked(packed_val: u32) Version {
        return .{
            .major = @intCast((packed_val >> 24) & 0xFF),
            .minor = @intCast((packed_val >> 12) & 0xFFF),
            .patch = @intCast(packed_val & 0xFFF),
        };
    }
};

// === Dictionary Type ===

pub const DictionaryType = enum(c_int) {
    raw = c.BROTLI_SHARED_DICTIONARY_RAW,
    serialized = c.BROTLI_SHARED_DICTIONARY_SERIALIZED,
};

// === Encoder Constants ===

pub const MIN_WINDOW_BITS: u5 = c.BROTLI_MIN_WINDOW_BITS;
pub const MAX_WINDOW_BITS: u5 = c.BROTLI_MAX_WINDOW_BITS;
pub const LARGE_MAX_WINDOW_BITS: u5 = c.BROTLI_LARGE_MAX_WINDOW_BITS;
pub const MIN_INPUT_BLOCK_BITS: u5 = c.BROTLI_MIN_INPUT_BLOCK_BITS;
pub const MAX_INPUT_BLOCK_BITS: u5 = c.BROTLI_MAX_INPUT_BLOCK_BITS;
pub const MIN_QUALITY: u4 = c.BROTLI_MIN_QUALITY;
pub const MAX_QUALITY: u4 = c.BROTLI_MAX_QUALITY;
pub const DEFAULT_QUALITY: u4 = c.BROTLI_DEFAULT_QUALITY;
pub const DEFAULT_WINDOW: u5 = c.BROTLI_DEFAULT_WINDOW;
pub const DEFAULT_BASE64_MODE: EncoderBase64Mode = @enumFromInt(c.BROTLI_DEFAULT_BASE64_MODE);
pub const DEFAULT_MAX_BASE64_REGIONS: u5 = c.BROTLI_DEFAULT_MAX_BASE64_REGIONS;
pub const DEFAULT_MODE: EncoderMode = .generic;

// === Shared Dictionary Constants ===

pub const SHARED_MIN_DICTIONARY_WORD_LENGTH: u6 = 4;
pub const SHARED_MAX_DICTIONARY_WORD_LENGTH: u5 = 31;
pub const SHARED_NUM_DICTIONARY_CONTEXTS: u7 = 64;
pub const SHARED_MAX_COMPOUND_DICTS: u4 = 15;
pub const SHARED_MAX_RAW_DICT_SIZE: usize = 1 << 27;

// === Error Sets ===

pub const AllocatorError = error{OutOfMemory};
pub const EncoderError = AllocatorError || error{InvalidParameter};
pub const DecoderError = AllocatorError || error{DecompressionFailed};
pub const DictionaryError = AllocatorError || error{InvalidDictionary};

// === Tests ===

test "encoderMode enum values" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(EncoderMode.generic));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(EncoderMode.text));
    try std.testing.expectEqual(@as(c_int, 2), @intFromEnum(EncoderMode.font));
}

test "encoderBase64Mode enum values" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(EncoderBase64Mode.disabled));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(EncoderBase64Mode.detection));
}

test "encoderParameter enum values" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(EncoderParameter.mode));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(EncoderParameter.quality));
    try std.testing.expectEqual(@as(c_int, 2), @intFromEnum(EncoderParameter.lgwin));
    try std.testing.expectEqual(@as(c_int, 3), @intFromEnum(EncoderParameter.lgblock));
    try std.testing.expectEqual(@as(c_int, 4), @intFromEnum(EncoderParameter.disable_literal_context_modeling));
    try std.testing.expectEqual(@as(c_int, 5), @intFromEnum(EncoderParameter.size_hint));
    try std.testing.expectEqual(@as(c_int, 6), @intFromEnum(EncoderParameter.large_window));
    try std.testing.expectEqual(@as(c_int, 7), @intFromEnum(EncoderParameter.npostfix));
    try std.testing.expectEqual(@as(c_int, 8), @intFromEnum(EncoderParameter.ndirect));
    try std.testing.expectEqual(@as(c_int, 9), @intFromEnum(EncoderParameter.stream_offset));
    try std.testing.expectEqual(@as(c_int, 10), @intFromEnum(EncoderParameter.base64_mode));
    try std.testing.expectEqual(@as(c_int, 11), @intFromEnum(EncoderParameter.max_base64_regions));
}

test "decoderParameter enum values" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(DecoderParameter.disable_ring_buffer_reallocation));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(DecoderParameter.large_window));
}

test "encoderOperation enum values" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(EncoderOperation.process));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(EncoderOperation.flush));
    try std.testing.expectEqual(@as(c_int, 2), @intFromEnum(EncoderOperation.finish));
    try std.testing.expectEqual(@as(c_int, 3), @intFromEnum(EncoderOperation.emit_metadata));
}

test "errorCode fromNative" {
    try std.testing.expectEqual(ErrorCode.no_error, ErrorCode.fromNative(0));
    try std.testing.expectEqual(ErrorCode.success, ErrorCode.fromNative(1));
    try std.testing.expectEqual(ErrorCode.needs_more_input, ErrorCode.fromNative(2));
    try std.testing.expectEqual(ErrorCode.needs_more_output, ErrorCode.fromNative(3));
    try std.testing.expectEqual(ErrorCode.error_format_exuberant_nibble, ErrorCode.fromNative(-1));
    try std.testing.expectEqual(ErrorCode.error_format_reserved, ErrorCode.fromNative(-2));
}

test "errorCode name" {
    try std.testing.expectEqualStrings("NO_ERROR", ErrorCode.no_error.name());
    try std.testing.expectEqualStrings("SUCCESS", ErrorCode.success.name());
    try std.testing.expectEqualStrings("ERROR_UNREACHABLE", ErrorCode.error_unreachable.name());
    try std.testing.expectEqualStrings("ERROR_FORMAT_DISTANCE", ErrorCode.error_format_distance.name());
}

test "version fromPacked" {
    const v = Version.fromPacked((1 << 24) | (2 << 12) | 3);
    try std.testing.expectEqual(@as(u8, 1), v.major);
    try std.testing.expectEqual(@as(u8, 2), v.minor);
    try std.testing.expectEqual(@as(u8, 3), v.patch);
}

test "version fromPacked zero" {
    const v = Version.fromPacked(0);
    try std.testing.expectEqual(@as(u8, 0), v.major);
    try std.testing.expectEqual(@as(u8, 0), v.minor);
    try std.testing.expectEqual(@as(u8, 0), v.patch);
}

test "decodeError fromNative with real error" {
    const handle = c.BrotliDecoderCreateInstance(null, null, null);
    defer c.BrotliDecoderDestroyInstance(handle);
    const corrupt = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    var available_in: usize = corrupt.len;
    var next_in: [*c]const u8 = &corrupt;
    var available_out: usize = 256;
    var buf: [256]u8 = undefined;
    var next_out: [*c]u8 = &buf;
    _ = c.BrotliDecoderDecompressStream(handle, &available_in, &next_in, &available_out, &next_out, null);
    const err = DecodeError.fromNative(handle);
    try std.testing.expect(err.code != .no_error);
    try std.testing.expect(err.message.len > 0);
}

test "streamResult fields" {
    const result = StreamResult{
        .bytes_consumed = 10,
        .bytes_produced = 20,
        .has_more_output = true,
        .is_finished = false,
    };
    try std.testing.expectEqual(@as(usize, 10), result.bytes_consumed);
    try std.testing.expectEqual(@as(usize, 20), result.bytes_produced);
    try std.testing.expect(result.has_more_output);
    try std.testing.expect(!result.is_finished);
}

test "encoder constants values" {
    try std.testing.expectEqual(@as(u5, 10), MIN_WINDOW_BITS);
    try std.testing.expectEqual(@as(u5, 24), MAX_WINDOW_BITS);
    try std.testing.expectEqual(@as(u5, 30), LARGE_MAX_WINDOW_BITS);
    try std.testing.expectEqual(@as(u5, 16), MIN_INPUT_BLOCK_BITS);
    try std.testing.expectEqual(@as(u5, 24), MAX_INPUT_BLOCK_BITS);
    try std.testing.expectEqual(@as(u4, 0), MIN_QUALITY);
    try std.testing.expectEqual(@as(u4, 11), MAX_QUALITY);
    try std.testing.expectEqual(@as(u4, 11), DEFAULT_QUALITY);
    try std.testing.expectEqual(@as(u5, 22), DEFAULT_WINDOW);
}

test "encoder base64 constants" {
    try std.testing.expectEqual(EncoderBase64Mode.disabled, DEFAULT_BASE64_MODE);
    try std.testing.expectEqual(@as(u5, 16), DEFAULT_MAX_BASE64_REGIONS);
}

test "shared dictionary constants" {
    try std.testing.expectEqual(@as(u6, 4), SHARED_MIN_DICTIONARY_WORD_LENGTH);
    try std.testing.expectEqual(@as(u5, 31), SHARED_MAX_DICTIONARY_WORD_LENGTH);
    try std.testing.expectEqual(@as(u7, 64), SHARED_NUM_DICTIONARY_CONTEXTS);
    try std.testing.expectEqual(@as(u4, 15), SHARED_MAX_COMPOUND_DICTS);
}

test "dictionaryType enum values" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(DictionaryType.raw));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(DictionaryType.serialized));
}

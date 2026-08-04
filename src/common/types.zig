const std = @import("std");
const c = @import("../c.zig").c;

pub const DictionaryType = enum(c_int) {
    raw = c.BROTLI_SHARED_DICTIONARY_RAW,
    serialized = c.BROTLI_SHARED_DICTIONARY_SERIALIZED,
};

pub const EncoderMode = enum(c_int) {
    generic = c.BROTLI_MODE_GENERIC,
    text = c.BROTLI_MODE_TEXT,
    font = c.BROTLI_MODE_FONT,
};

pub const EncoderOperation = enum(c_int) {
    process = c.BROTLI_OPERATION_PROCESS,
    flush = c.BROTLI_OPERATION_FLUSH,
    finish = c.BROTLI_OPERATION_FINISH,
    emit_metadata = c.BROTLI_OPERATION_EMIT_METADATA,
};

pub const DecoderResultTag = enum {
    success,
    needs_more_input,
    needs_more_output,
    @"error",
};

pub const DecoderResult = union(DecoderResultTag) {
    success: void,
    needs_more_input: void,
    needs_more_output: void,
    @"error": DecodeError,
};

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

pub const StreamResult = struct {
    bytes_consumed: usize,
    bytes_produced: usize,
    has_more_output: bool,
    is_finished: bool,
};

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

pub const AllocatorError = error{OutOfMemory};
pub const EncoderError = AllocatorError || error{InvalidParameter};
pub const DecoderError = AllocatorError || error{DecompressionFailed};
pub const DictionaryError = AllocatorError || error{InvalidDictionary};

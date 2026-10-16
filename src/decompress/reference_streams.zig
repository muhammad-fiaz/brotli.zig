//! Reference Brotli streams for compliance testing.

/// length of the generated payload the stream was built from; 0 means the
/// whole payload.
pub const ReferenceStream = struct {
    name: []const u8,
    quality: u32,
    head: usize,
    original_len: usize,
    compressed: []const u8,
    sha256: []const u8,
};

const raw_streams = @embedFile("reference_streams.bin");

pub const ref_0_compressed: []const u8 = raw_streams[0..2];
pub const ref_0_sha256: []const u8 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

pub const ref_1_compressed: []const u8 = raw_streams[2..8];
pub const ref_1_sha256: []const u8 = "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb";

pub const ref_2_compressed: []const u8 = raw_streams[8..25];
pub const ref_2_sha256: []const u8 = "46c0941f01bc4aba512b213ac665132ebc108b566ed6203a145d9016df7d1cc6";

pub const ref_3_compressed: []const u8 = raw_streams[25..1983];
pub const ref_3_sha256: []const u8 = "9fd0a6a12c6d4a6834140cdf88493569c8fedca573b0cd9ec0102adccd2ff11e";

pub const ref_4_compressed: []const u8 = raw_streams[1983..4241];
pub const ref_4_sha256: []const u8 = "9fd0a6a12c6d4a6834140cdf88493569c8fedca573b0cd9ec0102adccd2ff11e";

pub const ref_5_compressed: []const u8 = raw_streams[4241..4279];
pub const ref_5_sha256: []const u8 = "f9cb3e4e7e165accd8c291a042569458f6c13968297ccf604c9e2e64368352d3";

pub const ref_6_compressed: []const u8 = raw_streams[4279..4295];
pub const ref_6_sha256: []const u8 = "0c78e5c9d34b7e2fba080cd1e507aa60d009f677e4a202a93bd901e1d76de6f1";

pub const ref_7_compressed: []const u8 = raw_streams[4295..4308];
pub const ref_7_sha256: []const u8 = "40bd4474a301f59ef58c4e7d5c128e09154251d9f65a3816b728a9fe8987a0f7";

pub const ref_8_compressed: []const u8 = raw_streams[4308..7818];
pub const ref_8_sha256: []const u8 = "d9b7ff65e13cb6f8a5cad1ecd973fbeb15f5f112c9845b7c996e0e6cdf606854";

pub const ref_9_compressed: []const u8 = raw_streams[7818..9001];
pub const ref_9_sha256: []const u8 = "1147aeef1ff1cfac003d9c55203c43093284da93d813ba688c1a407754873964";

pub const ref_10_compressed: []const u8 = raw_streams[9001..9056];
pub const ref_10_sha256: []const u8 = "da8966801bd46b1db39f5df8e9c09c88a1490d892e538fcb07cfac87b1139cb7";

pub const ref_11_compressed: []const u8 = raw_streams[9056..9121];
pub const ref_11_sha256: []const u8 = "c81478bd5de64995cbf67afac5be3256b28df1e7523a32d08e02f0aba24e9940";

pub const ref_12_compressed: []const u8 = raw_streams[9121..11649];
pub const ref_12_sha256: []const u8 = "215a56a4bf24746f87ba7c5aee9df0faf683186217bf2c1848a1fbf52fb3847f";

pub const ref_13_compressed: []const u8 = raw_streams[11649..11676];
pub const ref_13_sha256: []const u8 = "c9307551120126e3367a070a57b42c48019cf4cc0d52fb8710c2a1394591fe25";

pub const reference_streams = [_]ReferenceStream{
    .{
        .name = "empty",
        .quality = 11,
        .head = 0,
        .original_len = 0,
        .compressed = ref_0_compressed,
        .sha256 = ref_0_sha256,
    },
    .{
        .name = "one_byte",
        .quality = 9,
        .head = 0,
        .original_len = 1,
        .compressed = ref_1_compressed,
        .sha256 = ref_1_sha256,
    },
    .{
        .name = "tiny",
        .quality = 5,
        .head = 0,
        .original_len = 12,
        .compressed = ref_2_compressed,
        .sha256 = ref_2_sha256,
    },
    .{
        .name = "text_en",
        .quality = 9,
        .head = 8000,
        .original_len = 8000,
        .compressed = ref_3_compressed,
        .sha256 = ref_3_sha256,
    },
    .{
        .name = "text_en",
        .quality = 1,
        .head = 8000,
        .original_len = 8000,
        .compressed = ref_4_compressed,
        .sha256 = ref_4_sha256,
    },
    .{
        .name = "text_utf8",
        .quality = 11,
        .head = 8000,
        .original_len = 8000,
        .compressed = ref_5_compressed,
        .sha256 = ref_5_sha256,
    },
    .{
        .name = "rep_periodic",
        .quality = 5,
        .head = 40000,
        .original_len = 40000,
        .compressed = ref_6_compressed,
        .sha256 = ref_6_sha256,
    },
    .{
        .name = "rle",
        .quality = 11,
        .head = 8000,
        .original_len = 8000,
        .compressed = ref_7_compressed,
        .sha256 = ref_7_sha256,
    },
    .{
        .name = "random",
        .quality = 6,
        .head = 4096,
        .original_len = 4096,
        .compressed = ref_8_compressed,
        .sha256 = ref_8_sha256,
    },
    .{
        .name = "nested_json",
        .quality = 4,
        .head = 8000,
        .original_len = 8000,
        .compressed = ref_9_compressed,
        .sha256 = ref_9_sha256,
    },
    .{
        .name = "dict_friendly",
        .quality = 11,
        .head = 16000,
        .original_len = 16000,
        .compressed = ref_10_compressed,
        .sha256 = ref_10_sha256,
    },
    .{
        .name = "blocky",
        .quality = 2,
        .head = 40000,
        .original_len = 40000,
        .compressed = ref_11_compressed,
        .sha256 = ref_11_sha256,
    },
    .{
        .name = "records",
        .quality = 10,
        .head = 6000,
        .original_len = 6000,
        .compressed = ref_12_compressed,
        .sha256 = ref_12_sha256,
    },
    .{
        .name = "zeros_ukkonooa",
        .quality = 11,
        .head = 0,
        .original_len = 262152,
        .compressed = ref_13_compressed,
        .sha256 = ref_13_sha256,
    },
};

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const portable = b.option(bool, "portable", "Build with BROTLI_BUILD_PORTABLE=1") orelse false;
    const shared = b.option(bool, "shared", "Build Brotli as a shared library instead of static") orelse false;

    const brotli_mod = b.addModule("brotli", .{
        .root_source_file = b.path("src/brotli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const c_lib = buildBrotliC(b, target, optimize, portable, shared);
    brotli_mod.linkLibrary(c_lib);
    brotli_mod.addIncludePath(b.path("c/include"));
    brotli_mod.addIncludePath(b.path("c"));

    b.installArtifact(c_lib);

    addTests(b, target, optimize, brotli_mod);
    addExamples(b, target, optimize, brotli_mod);
}

fn buildBrotliC(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    portable: bool,
    shared: bool,
) *std.Build.Step.Compile {
    const linkage: std.builtin.LinkMode = if (shared) .dynamic else .static;

    const c_root_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const c_lib = b.addLibrary(.{
        .name = "brotli",
        .root_module = c_root_mod,
        .linkage = linkage,
    });

    const flags: []const []const u8 = if (portable)
        &.{ "-DBROTLI_STATIC_COMPILATION", "-DBROTLI_BUILD_PORTABLE=1" }
    else
        &.{"-DBROTLI_STATIC_COMPILATION"};

    c_root_mod.addCSourceFiles(.{
        .root = b.path("c"),
        .files = &.{
            "common/dictionary.c",
            "common/context.c",
            "common/shared_dictionary.c",
            "common/transform.c",
            "common/platform.c",
            "common/constants.c",
            "dec/bit_reader.c",
            "dec/decode.c",
            "dec/huffman.c",
            "dec/prefix.c",
            "dec/state.c",
            "dec/static_init.c",
            "enc/backward_references.c",
            "enc/backward_references_hq.c",
            "enc/bit_cost.c",
            "enc/block_splitter.c",
            "enc/brotli_bit_stream.c",
            "enc/cluster.c",
            "enc/command.c",
            "enc/compound_dictionary.c",
            "enc/compress_fragment.c",
            "enc/compress_fragment_two_pass.c",
            "enc/dictionary_hash.c",
            "enc/encode.c",
            "enc/encoder_dict.c",
            "enc/entropy_encode.c",
            "enc/fast_log.c",
            "enc/histogram.c",
            "enc/literal_cost.c",
            "enc/memory.c",
            "enc/metablock.c",
            "enc/static_dict.c",
            "enc/static_dict_lut.c",
            "enc/utf8_util.c",
            "enc/static_init.c",
        },
        .flags = flags,
    });

    c_root_mod.addIncludePath(b.path("c/include"));
    c_root_mod.addIncludePath(b.path("c"));

    return c_lib;
}

fn addTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    brotli_mod: *std.Build.Module,
) void {
    _ = target;
    _ = optimize;
    const test_step = b.step("test", "Run all tests");

    const unit_tests = b.addTest(.{
        .root_module = brotli_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}

fn addExamples(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    brotli_mod: *std.Build.Module,
) void {
    const examples_step = b.step("examples", "Build and install all examples");

    const example_files = [_][]const u8{
        "01_quick_compress",
        "02_custom_quality",
        "03_streaming_encode",
        "04_streaming_decode",
        "05_custom_allocator",
        "06_shared_dictionary",
        "07_large_window",
        "08_error_handling",
    };

    inline for (example_files) |name| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("brotli", brotli_mod);

        const exe = b.addExecutable(.{
            .name = name,
            .root_module = exe_mod,
        });
        const install_exe = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install_exe.step);
        examples_step.dependOn(&install_exe.step);
    }
}

const std = @import("std");
const builtin = @import("builtin");

pub fn linkPcre(libExe: *std.Build.Step.Compile) void {
    // Use vendored PCRE2 - we expect src/pcre2 to be present
    const pcre2BuildOptions = [_][]const u8{
        "-DPCRE2_CODE_UNIT_WIDTH=8",
        "-DPCRE2_STATIC",
        "-DHAVE_CONFIG_H",
    };
    libExe.addIncludePath(.{ .cwd_relative = "src/pcre2" });
    libExe.addCSourceFiles(.{ .files = &pcre2Sources, .flags = &pcre2BuildOptions });

    if (builtin.os.tag == .macos) {
        // useful for package maintainers
        // see https://github.com/ziglang/zig/issues/13388
        libExe.headerpad_max_install_names = true;
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const lib_only: bool = b.option(bool, "lib-only", "Only compile the library") orelse false;
    const skip_lib: bool = b.option(bool, "skip-lib", "Skip compiling the library") orelse false;
    const wasm: bool = b.option(bool, "wasm", "Compile the wasm library") orelse false;

    // Main build step
    if (!lib_only and !wasm) {
        const fastfec_cli = b.addExecutable(.{ .name = "fastfec", .target = target, .optimize = optimize });

        fastfec_cli.linkLibC();

        fastfec_cli.addCSourceFiles(.{ .files = &libSources, .flags = &buildOptions });
        linkPcre(fastfec_cli);
        fastfec_cli.addCSourceFiles(.{ .files = &.{
            "src/cli.c",
            "src/main.c",
        }, .flags = &buildOptions });
        b.installArtifact(fastfec_cli);
    }

    if (!wasm and !skip_lib) {
        // Library build step
        const fastfec_lib = b.addSharedLibrary(.{ .name = "fastfec", .version = null, .target = target, .optimize = optimize });
        if (builtin.os.tag == .macos) {
            // useful for package maintainers
            // see https://github.com/ziglang/zig/issues/13388
            fastfec_lib.headerpad_max_install_names = true;
        }
        fastfec_lib.linkLibC();
        fastfec_lib.addCSourceFiles(.{ .files = &libSources, .flags = &buildOptions });
        linkPcre(fastfec_lib);
        b.installArtifact(fastfec_lib);
    } else if (wasm) {
        // Wasm library build step
        const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
        const HasRootModuleInOptions = @hasField(std.Build.ExecutableOptions, "root_module");
        const fastfec_wasm = b.addExecutable(.{ .name = "fastfec", .root_module = if (HasRootModuleInOptions) b.createModule(.{ .target = wasm_target, .optimize = optimize }) else undefined });
        if (@hasDecl(@TypeOf(fastfec_wasm.*), "setTarget")) fastfec_wasm.setTarget(wasm_target);
        if (@hasDecl(@TypeOf(fastfec_wasm.*), "setOptimize")) fastfec_wasm.setOptimize(optimize);
        fastfec_wasm.entry = .disabled;
        fastfec_wasm.import_symbols = true;
        fastfec_wasm.linkLibC();
        fastfec_wasm.addCSourceFiles(.{ .files = &libSources, .flags = &buildOptions });
        linkPcre(fastfec_wasm);
        fastfec_wasm.addCSourceFile(.{ .file = .{ .cwd_relative = "src/wasm.c" }, .flags = &buildOptions });
        b.installArtifact(fastfec_wasm);
    }

    // Test step
    var prev_test_step: ?*std.Build.Step = null;
    for (tests) |test_file| {
        const base_file = std.fs.path.basename(test_file);
        const HasRootModuleInOptions = @hasField(std.Build.ExecutableOptions, "root_module");
        const subtest_exe = b.addExecutable(.{ .name = base_file, .root_module = if (HasRootModuleInOptions) b.createModule(.{ .target = target, .optimize = optimize }) else undefined });
        if (@hasDecl(@TypeOf(subtest_exe.*), "setTarget")) subtest_exe.setTarget(target);
        if (@hasDecl(@TypeOf(subtest_exe.*), "setOptimize")) subtest_exe.setOptimize(optimize);
        subtest_exe.linkLibC();
        subtest_exe.addCSourceFiles(.{ .files = &testIncludes, .flags = &buildOptions });
        linkPcre(subtest_exe);
        subtest_exe.addCSourceFile(.{ .file = .{ .cwd_relative = test_file }, .flags = &buildOptions });
        const subtest_cmd = b.addRunArtifact(subtest_exe);
        if (prev_test_step != null) {
            subtest_cmd.step.dependOn(prev_test_step.?);
        }
        prev_test_step = &subtest_cmd.step;
    }
    const test_steps = prev_test_step.?;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(test_steps);
}

const libSources = [_][]const u8{
    "src/buffer.c",
    "src/memory.c",
    "src/encoding.c",
    "src/csv.c",
    "src/writer.c",
    "src/fec.c",
    "src/regex.c",
};
const pcre2Sources = [_][]const u8{
    "src/pcre2/pcre2_auto_possess.c",
    "src/pcre2/pcre2_chartables.c",
    "src/pcre2/pcre2_compile.c",
    "src/pcre2/pcre2_config.c",
    "src/pcre2/pcre2_context.c",
    "src/pcre2/pcre2_convert.c",
    "src/pcre2/pcre2_dfa_match.c",
    "src/pcre2/pcre2_error.c",
    "src/pcre2/pcre2_extuni.c",
    "src/pcre2/pcre2_find_bracket.c",
    "src/pcre2/pcre2_match.c",
    "src/pcre2/pcre2_match_data.c",
    "src/pcre2/pcre2_newline.c",
    "src/pcre2/pcre2_ord2utf.c",
    "src/pcre2/pcre2_pattern_info.c",
    "src/pcre2/pcre2_script_run.c",
    "src/pcre2/pcre2_serialize.c",
    "src/pcre2/pcre2_string_utils.c",
    "src/pcre2/pcre2_study.c",
    "src/pcre2/pcre2_substitute.c",
    "src/pcre2/pcre2_substring.c",
    "src/pcre2/pcre2_tables.c",
    "src/pcre2/pcre2_ucd.c",
    "src/pcre2/pcre2_ucptables.c",
    "src/pcre2/pcre2_valid_utf.c",
    "src/pcre2/pcre2_xclass.c",
};
const tests = [_][]const u8{ "src/buffer_test.c", "src/csv_test.c", "src/writer_test.c", "src/cli_test.c" };
const testIncludes = [_][]const u8{ "src/buffer.c", "src/memory.c", "src/encoding.c", "src/csv.c", "src/writer.c", "src/regex.c", "src/cli.c" };
const buildOptions = [_][]const u8{
    "-std=c11",
    "-pedantic",
    "-std=gnu99",
    "-Wall",
    "-W",
    "-Wno-missing-field-initializers",
};

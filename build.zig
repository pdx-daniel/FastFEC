const std = @import("std");
const builtin = @import("builtin");

pub fn linkPcre(libExe: *std.Build.Step.Compile, b: *std.Build) void {
    // Prefer vendored PCRE2 if present in src/pcre2; otherwise, link system pcre2-8
    if (std.fs.cwd().openDir("src/pcre2", .{ .iterate = true })) |dir_val| {
        var dir = dir_val;
        defer dir.close();
        var files = std.ArrayListUnmanaged([]const u8){};
        defer files.deinit(b.allocator);
        var it = dir.iterate();
        while (it.next() catch null) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                const path = std.fmt.allocPrint(b.allocator, "src/pcre2/{s}", .{entry.name}) catch continue;
                files.append(b.allocator, path) catch continue;
            }
        }

        if (files.items.len > 0) {
            const pcre2BuildOptions = [_][]const u8{
                "-DPCRE2_CODE_UNIT_WIDTH=8",
                "-DPCRE2_STATIC",
                "-DHAVE_CONFIG_H",
            };
            libExe.addIncludePath(.{ .cwd_relative = "src/pcre2" });
            libExe.addCSourceFiles(.{ .files = files.items, .flags = &pcre2BuildOptions });
        }
    } else |_| {
        // No vendored PCRE2 present; error for wasm builds and suggest installing pcre2 for host builds
        // Keep silent here; our project expects src/pcre2 to be present
    }
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
        var fastfec_cli = b.addExecutable(.{ .name = "fastfec", .root_module = b.createModule(.{ .target = target, .optimize = optimize }) });

        fastfec_cli.linkLibC();

        fastfec_cli.addCSourceFiles(.{ .files = &libSources, .flags = &buildOptions });
        linkPcre(fastfec_cli, b);
        fastfec_cli.addCSourceFiles(.{ .files = &.{
            "src/cli.c",
            "src/main.c",
        }, .flags = &buildOptions });
        b.installArtifact(fastfec_cli);
    }

    if (!wasm and !skip_lib) {
        // Library build step (skip on Zig 0.15 where addSharedLibrary is missing)
        if (@hasDecl(@TypeOf(b.*), "addSharedLibrary")) {
            var fastfec_lib = b.addSharedLibrary(.{ .name = "fastfec", .version = null, .root_module = b.createModule(.{ .target = target, .optimize = optimize }) });
            if (builtin.os.tag == .macos) {
                fastfec_lib.headerpad_max_install_names = true;
            }
            fastfec_lib.linkLibC();
            fastfec_lib.addCSourceFiles(.{ .files = &libSources, .flags = &buildOptions });
            linkPcre(fastfec_lib, b);
            b.installArtifact(fastfec_lib);
        }
    } else if (wasm) {
        // Wasm library build step
        const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
        var fastfec_wasm = b.addExecutable(.{ .name = "fastfec", .root_module = b.createModule(.{ .target = wasm_target, .optimize = optimize }) });
        fastfec_wasm.entry = .disabled;
        fastfec_wasm.import_symbols = true;
        fastfec_wasm.root_module.export_symbol_names = &.{"wasmFec"};
        fastfec_wasm.linkLibC();
        fastfec_wasm.addCSourceFiles(.{ .files = &libSources, .flags = &buildOptions });
        linkPcre(fastfec_wasm, b);
        fastfec_wasm.addCSourceFile(.{ .file = .{ .cwd_relative = "src/wasm.c" }, .flags = &buildOptions });
        b.installArtifact(fastfec_wasm);
    }

    // Test step
    var prev_test_step: ?*std.Build.Step = null;
    for (tests) |test_file| {
        const base_file = std.fs.path.basename(test_file);
        var subtest_exe = b.addExecutable(.{ .name = base_file, .root_module = b.createModule(.{ .target = target, .optimize = optimize }) });
        subtest_exe.linkLibC();
        subtest_exe.addCSourceFiles(.{ .files = &testIncludes, .flags = &buildOptions });
        linkPcre(subtest_exe, b);
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

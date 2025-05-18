const std = @import("std");
const builtin = @import("builtin");
// `dependencies` field can't be represented https://github.com/ziglang/zig/issues/22775
const build_zon: struct {
    name: @Type(.enum_literal),
    version: []const u8,
    fingerprint: u64,
    minimum_zig_version: []const u8,
    dependencies: struct {},
    paths: []const []const u8,
} = @import("build.zig.zon");
const test_cases = @import("test/cases.zig");

const CompileFlags = std.BoundedArray([]const u8, 64);

comptime {
    checkVersion();
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const no_bin = b.option(bool, "no-bin", "skip emitting binary for incremental compilation checks") orelse false;
    const strip = b.option(bool, "strip", "Strip debug information") orelse false;
    const want_lto = b.option(bool, "lto", "Enable link time optimization") orelse false;
    const use_llvm = b.option(bool, "llvm", "Use the llvm codegen backend") orelse false;
    const use_lld = b.option(bool, "lld", "Use the llvm's lld linker") orelse false;
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Choose linkage of czalloc") orelse .static;

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .sanitize_c = .full,
        .stack_check = true,
        .strip = strip,
    });

    const lib = b.addLibrary(.{
        .name = "czalloc",
        .linkage = linkage,
        .root_module = lib_mod,
        .use_lld = use_lld,
        .use_llvm = use_llvm,
    });
    lib.pie = use_llvm;
    lib.want_lto = want_lto;

    if (no_bin) {
        const czalloc = lib.getEmittedBin();
        b.addNamedLazyPath("czalloc", czalloc);
    } else {
        b.installArtifact(lib);
    }

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    var compile_flags_buf = CompileFlags.init(0) catch @panic("Buffer Overflow");
    const cflags = loadCompileFlags("compile_flags.txt", &compile_flags_buf);

    try test_cases.addCase(b, test_step, .{
        .target = target,
        .czalloc_lib = lib,
        .cflags = cflags,
        .optimize_mode = &.{ .Debug, .ReleaseFast },
        .use_lld = use_lld,
        .use_llvm = use_llvm,
        .pie = use_llvm,
        .want_lto = want_lto,
        .strip = strip,
    });
}

fn loadCompileFlags(comptime path: []const u8, array: *CompileFlags) []const []const u8 {
    //use -Werror for compilation only
    array.appendAssumeCapacity("-Werror");

    const compile_flags = @embedFile(path);
    var itr = std.mem.splitScalar(u8, compile_flags, '\n');
    while (itr.next()) |line| {
        if (line.len == 0) break; // End of Stream
        if (line[0] == '#') continue; // A comment
        array.appendAssumeCapacity(line);
    }
    return array.constSlice();
}

// ensures the currently in-use zig version is at least the minimum required
fn checkVersion() void {
    const supported_version = std.SemanticVersion.parse(build_zon.minimum_zig_version) catch unreachable;

    const current_version = builtin.zig_version;
    const order = current_version.order(supported_version);
    if (order == .lt) {
        @compileError(std.fmt.comptimePrint("Update your zig toolchain to >= {s}", .{build_zon.minimum_zig_version}));
    }
}

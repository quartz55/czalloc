const std = @import("std");
const Array = std.BoundedArray([]const u8, 128);

pub fn addCase(
    b: *std.Build,
    tests_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    czalloc_lib: *std.Build.Step.Compile,
) void {
    const run_step = b.step("run-cases", "Run the test cases");
    tests_step.dependOn(run_step);

    var dir = b.build_root.handle.openDir("test/cases", .{ .iterate = true }) catch |err| {
        const fail_step = b.addFail(b.fmt("unable to open test/cases: {s}\n", .{@errorName(err)}));
        run_step.dependOn(&fail_step.step);
        return;
    };
    defer dir.close();

    var it = try dir.walk(b.allocator);
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;

        const annotated_case_name = b.fmt("run-translated {s}", .{entry.basename});

        const src_input = @embedFile(entry.path);
        const write_src = b.addWriteFiles();
        const file_source = write_src.add("tmp.c", src_input);

        var array: Array = .init(0) catch @panic("Buffer Overflow");
        const cflags = loadCompileFlags("compile_flags.txt", &array);

        const c_module = b.createModule(.{
            .link_libc = true,
            .optimize = .Debug,
            .sanitize_c = .full,
            .stack_check = true,
            .stack_protector = true,
            .strip = false,
            .target = target,
        });
        c_module.linkLibrary(czalloc_lib);
        c_module.addCSourceFile(.{
            .file = file_source,
            .flags = cflags,
            .language = .c,
        });
        if (target.result.isGnuLibC()) {
            c_module.addCMacro("_FORTIFY_SOURCE", "3");
        }

        const c_exe = b.addExecutable(.{
            .target = target,
            .optimize = .Debug,
            .root_module = c_module,
        });
        c_exe.step.name = b.fmt("{s} test", .{annotated_case_name});

        const run_exe = b.addRunArtifact(c_exe);
        run_exe.step.name = b.fmt("{s} run", .{annotated_case_name});
        run_exe.expectExitCode(0);
        run_exe.skip_foreign_checks = true;

        run_step.dependOn(&run_exe.step);
    }
}

fn loadCompileFlags(comptime path: []const u8, array: *Array) []const []const u8 {
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

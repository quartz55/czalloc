const std = @import("std");

pub const CaseOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize_mode: []const std.builtin.OptimizeMode,
    cflags: []const []const u8,
    czalloc_lib: *std.Build.Step.Compile,
    use_lld: bool,
    use_llvm: bool,
    pie: bool,
    want_lto: bool,
    strip: bool,
};

pub fn addCase(
    b: *std.Build,
    tests_step: *std.Build.Step,
    options: CaseOptions,
) !void {
    const run_step = b.step("run-cases", "Run the test cases");
    tests_step.dependOn(run_step);

    var dir = b.build_root.handle.openDir("test/cases", .{ .iterate = true }) catch |err| {
        const fail_step = b.addFail(b.fmt("unable to open test/cases: {s}\n", .{@errorName(err)}));
        run_step.dependOn(&fail_step.step);
        return;
    };
    defer dir.close();

    const max_file_size = std.fmt.parseIntSizeSuffix("1MiB", 10) catch unreachable;

    var it = try dir.walk(b.allocator);
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;

        const src_input = try dir.readFileAlloc(b.allocator, entry.path, max_file_size);
        const write_src = b.addWriteFiles();
        const file_source = write_src.add("tmp.c", src_input);

        for (options.optimize_mode) |optimize| {
            const annotated_case_name = b.fmt(
                "run-{s}-{s}",
                .{ entry.basename, @tagName(optimize) },
            );

            const c_module = b.createModule(.{
                .target = options.target,
                .optimize = optimize,
                .strip = options.strip,
                .link_libc = true,
                .sanitize_c = .full,
                .stack_check = true,
                .stack_protector = true,
            });
            c_module.linkLibrary(options.czalloc_lib);
            c_module.addCSourceFile(.{
                .file = file_source,
                .flags = options.cflags,
                .language = .c,
            });
            if (options.target.result.isGnuLibC()) {
                switch (optimize) {
                    .Debug => {},
                    else => {
                        c_module.addCMacro("_FORTIFY_SOURCE", "3");
                    },
                }
            }

            const c_exe = b.addExecutable(.{
                .name = annotated_case_name,
                .optimize = optimize,
                .root_module = c_module,
                .use_lld = options.use_lld,
                .use_llvm = options.use_llvm,
            });
            c_exe.pie = options.pie;
            c_exe.want_lto = options.want_lto;
            c_exe.step.name = b.fmt("{s} test", .{annotated_case_name});

            const run_exe = b.addRunArtifact(c_exe);
            run_exe.step.name = b.fmt("{s} run", .{annotated_case_name});
            _ = run_exe.captureStdErr(); //ignore output
            run_exe.expectExitCode(0);
            run_exe.skip_foreign_checks = true;

            run_step.dependOn(&run_exe.step);
        }
    }
}

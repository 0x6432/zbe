const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("zbe_native", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const executable = b.addExecutable(.{
        .name = "zbe-native",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/driver.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(executable);
    const tests = b.addTest(.{ .root_module = module });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Test the independent rewrite").dependOn(&run_tests.step);
    b.default_step.dependOn(&tests.step);
}

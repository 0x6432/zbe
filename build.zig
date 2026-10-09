const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "qbe",
        .root_module = mod,
    });
    b.installArtifact(exe);

    // library mode: Zig module "qbe" and static C library libqbe.a
    _ = b.addModule("qbe", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .name = "qbe",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(lib);
    b.installFile("include/qbe.h", "include/qbe.h");

    const run = b.addRunArtifact(exe);
    b.step("run", "Run qbe").dependOn(&run.step);

    const unit = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/unit_tests.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(unit).step);
}

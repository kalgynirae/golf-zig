const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bounded_array = b.dependency("bounded_array", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_artifact = raylib.artifact("raylib");

    const exe = b.addExecutable(.{
        .name = "golf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "bounded_array", .module = bounded_array.module("bounded_array") },
                .{ .name = "raylib", .module = raylib.module("raylib") },
                .{ .name = "raygui", .module = raylib.module("raygui") },
            },
        }),
    });
    exe.linkLibrary(raylib_artifact);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);
}

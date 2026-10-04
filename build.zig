const std = @import("std");
const builtin = @import("builtin");

const build_utils = @import("zigmkay/build_utils.zig");
pub const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) void {
    const zigmkay_mod = b.addModule("zigmkay", .{
        .root_source_file = .{
            .src_path = .{ .owner = b, .sub_path = "zigmkay/src/root.zig" },
        },
    });

    const test_run_step = b.step("test", "Run unit tests");
    build_utils.add_test_steps(b, zigmkay_mod, test_run_step, "zigmkay/tests");

    if (builtin.os.tag == .macos) {
        const rawhid_monitor = b.addExecutable(.{
            .name = "rawhid-monitor",
            .root_module = b.createModule(.{ .target = b.graph.host }),
        });
        rawhid_monitor.root_module.addCSourceFile(.{
            .file = b.path("tools/rawhid_monitor.c"),
            .flags = &.{"-std=c11"},
        });
        rawhid_monitor.root_module.link_libc = true;
        rawhid_monitor.root_module.linkFramework("IOKit", .{});
        rawhid_monitor.root_module.linkFramework("CoreFoundation", .{});

        const run_rawhid_monitor = b.addRunArtifact(rawhid_monitor);
        const rawhid_monitor_step = b.step("rawhid-monitor", "Observe ZigMkay Raw HID key events");
        rawhid_monitor_step.dependOn(&run_rawhid_monitor.step);
    }
}

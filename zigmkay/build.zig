const std = @import("std");

pub const microzig = @import("microzig");
const build_utils = @import("build_utils.zig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) void {
    const zigmkay_mod = b.addModule("zigmkay", .{
        .root_source_file = .{
            .src_path = .{ .owner = b, .sub_path = "src/root.zig" },
        },
    });
    const test_run_step = b.step("test", "Run unit tests");
    build_utils.add_test_steps(b, zigmkay_mod, test_run_step, "tests");

    // Host tool for downstream packages, see addPicotoolFlash.
    const picotool_flash = b.addExecutable(.{
        .name = "picotool_flash",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/picotool_flash.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    b.installArtifact(picotool_flash);
}

/// Adds an uncached run step that flashes `firmware_uf2` with picotool: it
/// reports the UF2 hash, waits for a device in BOOTSEL mode, loads and verifies
/// the firmware, and reboots. The UF2 must carry the RP2040 family ID, e.g.
/// `firmware.get_emitted_bin(.{ .uf2 = .{ .family_id = .RP2040 } })`.
///
/// Usage from a downstream build.zig:
///     const zigmkay_dep = b.dependency("zigmkay", .{});
///     const flash = @import("zigmkay").addPicotoolFlash(b, zigmkay_dep, firmware_uf2);
///     b.step("flash", "Flash with picotool").dependOn(&flash.step);
pub fn addPicotoolFlash(b: *std.Build, zigmkay_dep: *std.Build.Dependency, firmware_uf2: std.Build.LazyPath) *std.Build.Step.Run {
    const flash_command = b.addRunArtifact(zigmkay_dep.artifact("picotool_flash"));
    flash_command.addFileArg(firmware_uf2);
    flash_command.has_side_effects = true;
    return flash_command;
}

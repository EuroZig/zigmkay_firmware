const std = @import("std");
const builtin = @import("builtin");

const zigmkay_build = @import("zigmkay");
pub const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub const boards = @import("keyboards/boards.zig");
pub const addKeyboardFirmware = @import("keyboards/build_api.zig").addKeyboardFirmware;
pub const FirmwareSources = @import("keyboards/build_api.zig").Sources;
pub const device_protocol_version: u8 = 2;
pub const default_keymap_catalog_version: u16 = 1;
pub const flash_wrapper_contract_version: u16 = 1;
pub const processing_descriptor_version: u16 = 1;
pub const addPicotoolFlash = zigmkay_build.addPicotoolFlash;
pub const FlashSteps = zigmkay_build.FlashSteps;

/// Adds the `flash`, `flash_pt` and `flash_mount` steps and the
/// `-Dflash-mount` option for `firmware_uf2`. `firmware_dep` is this package
/// (zigmkay_firmware) as a dependency of the calling package:
///     const firmware_dep = b.dependency("zigmkay_firmware", .{});
///     _ = @import("zigmkay_firmware").addFlashSteps(b, firmware_dep, firmware_uf2);
/// Call this helper only when explicitly enabling flash steps in the downstream
/// build: registering the picotool step prepares the optional picotool dependency.
pub fn addFlashSteps(b: *std.Build, firmware_dep: *std.Build.Dependency, firmware_uf2: std.Build.LazyPath) FlashSteps {
    const zigmkay_dep = firmware_dep.builder.dependency("zigmkay", .{ .@"flash-tools" = true });
    return zigmkay_build.addFlashSteps(b, zigmkay_dep, firmware_uf2);
}

pub fn build(b: *std.Build) void {
    const zigmkay_mod = b.addModule("zigmkay", .{
        .root_source_file = .{
            .src_path = .{ .owner = b, .sub_path = "zigmkay/src/root.zig" },
        },
    });
    const keycodes = b.createModule(.{
        .root_source_file = b.path("zkeycodes/root.zig"),
        .imports = &.{.{ .name = "zigmkay", .module = zigmkay_mod }},
    });
    _ = b.addModule("default-keymaps", .{
        .root_source_file = b.path("keyboards/default_keymaps.zig"),
        .imports = &.{ .{ .name = "zigmkay", .module = zigmkay_mod }, .{ .name = "zkeycodes", .module = keycodes } },
    });

    const test_run_step = b.step("test", "Run unit tests");
    zigmkay_build.add_test_steps(b, zigmkay_mod, test_run_step, "zigmkay/tests");

    // Downstream preparation explicitly requests these named artifacts from the
    // root package; ordinary root builds never resolve the picotool dependency.
    if (b.option(bool, "flash-tools", "Prepare bounded picotool tools for downstream consumers") orelse false) {
        const tools = b.dependency("zigmkay", .{ .@"flash-tools" = true });
        b.installArtifact(tools.artifact("picotool_flash"));
        b.addNamedLazyPath("picotool", tools.namedLazyPath("picotool"));
    }

    if (builtin.os.tag == .macos) {
        const zigmkay_dep = b.dependency("zigmkay", .{});
        const run_rawhid_monitor = b.addRunArtifact(zigmkay_dep.artifact("rawhid-monitor"));
        const rawhid_monitor_step = b.step("rawhid-monitor", "Observe ZigMkay Raw HID key events");
        rawhid_monitor_step.dependOn(&run_rawhid_monitor.step);
    }
}

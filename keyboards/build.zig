const std = @import("std");
const builtin = @import("builtin");

const microzig = @import("microzig");
const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

const KeyboardSample = struct {
    name: []const u8,
    root_source_file: []const u8,
};

const keyboard_samples = [_]KeyboardSample{
    .{ .name = "clacky_chan", .root_source_file = "my_keyboards/rollercole/clacky_chan.zig" },
    .{ .name = "clackychan_colemak", .root_source_file = "my_keyboards/janbeelte/clackychan_colemak/main.zig" },
    .{ .name = "lk1", .root_source_file = "my_keyboards/rollercole/leonardo_keycaprio_0_1.zig" },
    .{ .name = "lk2", .root_source_file = "my_keyboards/rollercole/leonardo_keycaprio_0_2.zig" },
    .{ .name = "lk6", .root_source_file = "my_keyboards/rollercole/leonardo_keycaprio_0_6.zig" },
    .{ .name = "lk7", .root_source_file = "my_keyboards/rollercole/leonardo_keycaprio_0_7.zig" },
    .{ .name = "encoder_demo", .root_source_file = "my_keyboards/rollercole/encoder_demo.zig" },
    .{ .name = "dasbob", .root_source_file = "examples/dasbob/main.zig" },
    .{ .name = "tuckytwotimes", .root_source_file = "my_keyboards/rollercole/tuckytwotimes.zig" },
    .{ .name = "molekula", .root_source_file = "my_keyboards/molekula/main.zig" },
};

pub fn build(b: *std.Build) void {
    const selected_keyboard = b.option([]const u8, "keyboard", keyboardOptionDescription(b)) orelse keyboard_samples[0].name;

    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const target = mb.ports.rp2xxx.boards.raspberrypi.pico.*;
    const optimize: std.builtin.OptimizeMode = .ReleaseSafe;

    const zigmkay_dep = b.dependency("zigmkay", .{});
    const zigmkay_mod = zigmkay_dep.module("zigmkay");

    const zkeycodes_dep = b.dependency("zkeycodes", .{});
    const zkeycodes_mod = zkeycodes_dep.module("zkeycodes");

    const sample = findSample(selected_keyboard) orelse {
        printAvailableSamples();
        std.debug.panic("Unknown keyboard sample: '{s}'", .{selected_keyboard});
    };

    const firmware = mb.add_firmware(.{
        .name = "zigmkay_firmware",
        .target = &target,
        .optimize = optimize,
        .root_source_file = b.path(sample.root_source_file),
    });

    firmware.add_app_import("zigmkay", zigmkay_mod, .{ .depend_on_microzig = true });
    firmware.add_app_import("zkeycodes", zkeycodes_mod, .{ .depend_on_microzig = true });
    mb.install_firmware(firmware, .{});

    const firmware_uf2 = firmware.get_emitted_bin(.{ .uf2 = .{} });
    b.addNamedLazyPath("firmware_uf2", firmware_uf2);

    const flash_mount_step = b.step("flash_mount", "Build and flash the firmware through a mounted RP2 bootloader volume");
    const flash_command = b.addSystemCommand(&.{ "sh", "-c", "until diskutil info \"$2\" >/dev/null 2>&1; do sleep 0.2; done; sleep 0.5; cp \"$1\" \"$2/firmware.uf2\" && sync", "sh" });
    flash_command.addFileArg(firmware_uf2);
    flash_command.addArg(b.option([]const u8, "flash-mount", "Mounted RP2 bootloader volume") orelse "/Volumes/RPI-RP2");
    flash_command.has_side_effects = true;
    flash_mount_step.dependOn(&flash_command.step);

    const flash_pt_step = b.step("flash_pt", "Build and flash the firmware with picotool");
    const flash_pt_command = addPicotoolFlashCommand(b, firmware_uf2);
    flash_pt_step.dependOn(&flash_pt_command.step);

    const flash_step = b.step("flash", "Build and flash the firmware using the host default");
    if (builtin.os.tag == .macos) {
        flash_step.dependOn(&flash_pt_command.step);
    } else {
        flash_step.dependOn(&flash_command.step);
    }
}

/// Waits for a BOOTSEL device, loads and verifies a UF2 image, then reboots the
/// device into application mode. The returned reboot command depends on the
/// whole sequence, so downstream steps only need to depend on the result.
pub fn addPicotoolFlashCommand(b: *std.Build, firmware_uf2: std.Build.LazyPath) *std.Build.Step.Run {
    const wait_for_pico = b.addExecutable(.{
        .name = "wait_for_pico",
        .root_module = b.createModule(.{
            .root_source_file = b.path("../tools/wait_for_pico.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    const wait_command = b.addRunArtifact(wait_for_pico);
    wait_command.has_side_effects = true;
    firmware_uf2.addStepDependencies(&wait_command.step);

    const load_command = b.addSystemCommand(&.{ "picotool", "load", "--force-no-reboot", "--verify" });
    load_command.addFileArg(firmware_uf2);
    load_command.has_side_effects = true;
    load_command.step.dependOn(&wait_command.step);

    const reboot_command = b.addSystemCommand(&.{ "picotool", "reboot", "--application" });
    reboot_command.has_side_effects = true;
    reboot_command.step.dependOn(&load_command.step);
    return reboot_command;
}

fn keyboardOptionDescription(b: *std.Build) []const u8 {
    var sample_names: [keyboard_samples.len][]const u8 = undefined;
    inline for (keyboard_samples, 0..) |sample, idx| {
        sample_names[idx] = sample.name;
    }

    const joined_samples = std.mem.join(b.allocator, ", ", sample_names[0..]) catch @panic("Failed to build keyboard sample list");
    return std.fmt.allocPrint(
        b.allocator,
        "Keyboard sample to build/flash (use: zig build -Dkeyboard=<name>, flash: zig build flash -Dkeyboard=<name>, picotool: zig build flash_pt -Dkeyboard=<name>, available: {s})",
        .{joined_samples},
    ) catch @panic("Failed to build keyboard option description");
}

fn findSample(name: []const u8) ?KeyboardSample {
    inline for (keyboard_samples) |sample| {
        if (std.mem.eql(u8, sample.name, name)) return sample;
    }
    return null;
}

fn printAvailableSamples() void {
    std.debug.print("Available keyboard samples:\n", .{});
    inline for (keyboard_samples) |sample| {
        std.debug.print("  - {s}\n", .{sample.name});
    }
    std.debug.print("zig build -Dkeyboard=<name>\t\tBuild the Firmware\n", .{});
    std.debug.print("zig build flash -Dkeyboard=<name>\tBuild & Flash using the host default\n", .{});
    std.debug.print("zig build flash_pt -Dkeyboard=<name>\tBuild & Flash with picotool\n\n", .{});
}

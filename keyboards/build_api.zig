const std = @import("std");
const boards = @import("boards.zig");

pub const Sources = struct {
    keyboards: std.Build.LazyPath,
    processor: std.Build.LazyPath,
    keycodes: std.Build.LazyPath,
};

/// Build with authoritative firmware wiring and an optional downstream keymap.
/// Each invocation owns its module graph; MicroZig imports cannot leak between
/// different firmware instances. No process runs or device access is scheduled.
pub fn addKeyboardFirmware(
    b: *std.Build,
    mb: anytype,
    target: anytype,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    board: boards.Entry,
    sources: Sources,
    supplied_keymap: ?std.Build.LazyPath,
) *@TypeOf(mb.*).Firmware {
    const firmware = mb.add_firmware(.{
        .name = name,
        .target = target,
        .optimize = optimize,
        .root_source_file = sources.keyboards.path(b, board.root_source_file),
    });
    const processor = b.createModule(.{ .root_source_file = sources.processor });
    const keycodes = b.createModule(.{
        .root_source_file = sources.keycodes,
        .imports = &.{.{ .name = "zigmkay", .module = processor }},
    });
    const keymap = b.createModule(.{
        .root_source_file = supplied_keymap orelse sources.keyboards.path(b, board.default_keymap),
        .imports = &.{
            .{ .name = "zigmkay", .module = processor },
            .{ .name = "zkeycodes", .module = keycodes },
        },
    });
    const validation = b.createModule(.{
        .root_source_file = sources.keyboards.path(b, "keymap_validation.zig"),
        .imports = &.{.{ .name = "zigmkay", .module = processor }},
    });
    firmware.add_app_import("zigmkay", processor, .{ .depend_on_microzig = true });
    firmware.add_app_import("zkeycodes", keycodes, .{ .depend_on_microzig = true });
    firmware.add_app_import("keymap", keymap, .{ .depend_on_microzig = true });
    firmware.add_app_import("keymap_validation", validation, .{});
    return firmware;
}

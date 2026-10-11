//! Portable default keymap inventory. One source module owns shared relative
//! imports; downstream consumers need neither MCU entrypoints nor local copies.
pub const boards = @import("boards.zig");
pub const processing_descriptors = @import("processing_descriptors.zig");
const std = @import("std");
// Zig requires literal import operands. These are source bindings, not a second
// board inventory; selector order and multiplicity come only from boards.zig.
const Binding = struct { path: []const u8, Profile: type };
const bindings = [_]Binding{
    .{ .path = "my_keyboards/rollercole/shared_keymap_28_1.zig", .Profile = @import("my_keyboards/rollercole/shared_keymap_28_1.zig") },
    .{ .path = "my_keyboards/janbeelte/clackychan_colemak_keymap.zig", .Profile = @import("my_keyboards/janbeelte/clackychan_colemak_keymap.zig") },
    .{ .path = "my_keyboards/janbeelte/keycaprio_colemak_keymap.zig", .Profile = @import("my_keyboards/janbeelte/keycaprio_colemak_keymap.zig") },
    .{ .path = "my_keyboards/janbeelte/keycaprio_us_intl_keymap.zig", .Profile = @import("my_keyboards/janbeelte/keycaprio_us_intl_keymap.zig") },
    .{ .path = "my_keyboards/rollercole/shared_keymap_3x5_2.zig", .Profile = @import("my_keyboards/rollercole/shared_keymap_3x5_2.zig") },
    .{ .path = "my_keyboards/rollercole/encoder_demo_keymap.zig", .Profile = @import("my_keyboards/rollercole/encoder_demo_keymap.zig") },
    .{ .path = "examples/dasbob/keymap.zig", .Profile = @import("examples/dasbob/keymap.zig") },
    .{ .path = "my_keyboards/molekula/keymap.zig", .Profile = @import("my_keyboards/molekula/keymap.zig") },
};
pub const profiles = blk: {
    var result: [boards.entries.len]type = undefined;
    for (boards.entries, 0..) |board, index| {
        var selected: ?type = null;
        for (bindings) |binding| if (std.mem.eql(u8, binding.path, board.default_keymap)) {
            selected = binding.Profile;
        };
        result[index] = selected orelse @compileError("Board default keymap is not bound by portable catalog");
    }
    break :blk result;
};

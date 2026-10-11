//! Firmware-owned logical processing contracts, extracted from board roots.
//! No MCU imports, display geometry, GPIO digest or live identity is implied.
const std = @import("std");
const core = @import("zigmkay").core;
const boards = @import("boards.zig");
pub const version: u16 = 1;
pub const Entry = struct {
    selector: []const u8,
    key_count: usize,
    sides: []const core.Side,
    /// Action slots, not encoder devices: CW and CCW have separate indexes.
    encoder_actions: usize,
};

const split30 = [_]core.Side{ .L, .L, .L, .L, .L, .R, .R, .R, .R, .R, .L, .L, .L, .L, .L, .R, .R, .R, .R, .R, .L, .L, .L, .L, .R, .R, .R, .R, .X, .X };
const split34 = [_]core.Side{ .L, .L, .L, .L, .L, .R, .R, .R, .R, .R, .L, .L, .L, .L, .L, .R, .R, .R, .R, .R, .L, .L, .L, .L, .L, .R, .R, .R, .R, .R, .X, .X, .X, .X };
const molekula38 = [_]core.Side{
    .L, .L, .L, .L, .L, .R, .R, .R, .R, .R,
    .L, .L, .L, .L, .L, .L, .R, .R, .R, .R,
    .R, .R, .L, .L, .L, .L, .L, .R, .R, .R,
    .R, .R, .X, .X, .X, .X, .X, .X,
};
// These roots omitted side_definition, whose processing default is all X.
const dasbob36: [36]core.Side = @splat(.X);
const encoder1: [1]core.Side = @splat(.X);

const Binding = struct { root: []const u8, sides: []const core.Side, encoder_actions: usize = 0 };
const bindings = [_]Binding{
    .{ .root = "my_keyboards/rollercole/clacky_chan.zig", .sides = &split30 },
    .{ .root = "my_keyboards/janbeelte/clackychan_main.zig", .sides = &split30 },
    .{ .root = "my_keyboards/janbeelte/keycaprio_main_0_4.zig", .sides = &split30 },
    .{ .root = "my_keyboards/janbeelte/keycaprio_main_0_6.zig", .sides = &split34 },
    .{ .root = "my_keyboards/janbeelte/keycaprio_main_0_7.zig", .sides = &split34 },
    .{ .root = "my_keyboards/rollercole/leonardo_keycaprio_0_1.zig", .sides = &split30 },
    .{ .root = "my_keyboards/rollercole/leonardo_keycaprio_0_2.zig", .sides = &split30 },
    .{ .root = "my_keyboards/rollercole/leonardo_keycaprio_0_6.zig", .sides = &split34 },
    .{ .root = "my_keyboards/rollercole/leonardo_keycaprio_0_7.zig", .sides = &split34 },
    .{ .root = "my_keyboards/rollercole/encoder_demo.zig", .sides = &encoder1, .encoder_actions = 2 },
    .{ .root = "examples/dasbob/main.zig", .sides = &dasbob36 },
    .{ .root = "my_keyboards/rollercole/tuckytwotimes.zig", .sides = &split30, .encoder_actions = 4 },
    .{ .root = "my_keyboards/molekula/main.zig", .sides = &molekula38 },
};

pub const entries = blk: {
    @setEvalBranchQuota(100_000);
    var result: [boards.entries.len]Entry = undefined;
    for (boards.entries, 0..) |board, index| {
        var selected: ?Binding = null;
        for (bindings) |binding| if (std.mem.eql(u8, board.root_source_file, binding.root)) {
            if (selected != null) @compileError("Duplicate processing descriptor root binding");
            selected = binding;
        };
        const binding = selected orelse @compileError("Missing firmware processing descriptor");
        result[index] = .{ .selector = board.name, .key_count = binding.sides.len, .sides = binding.sides, .encoder_actions = binding.encoder_actions };
    }
    break :blk result;
};

pub fn find(selector: []const u8) ?*const Entry {
    for (&entries) |*entry| if (std.mem.eql(u8, selector, entry.selector)) return entry;
    return null;
}

test "processing inventory covers every selector and keeps encoder slot indexes" {
    try std.testing.expectEqual(boards.entries.len, entries.len);
    for (entries) |entry| {
        try std.testing.expectEqualStrings(entry.selector, find(entry.selector).?.selector);
        try std.testing.expectEqual(entry.key_count, entry.sides.len);
        try std.testing.expect(entry.key_count > 0 and entry.key_count <= 127);
    }
    try std.testing.expectEqual(@as(usize, 4), find("tuckytwotimes").?.encoder_actions);
    try std.testing.expectEqual(@as(usize, 2), find("encoder_demo").?.encoder_actions);
    try std.testing.expectEqual(@as(usize, 0), find("molekula").?.encoder_actions);
    for (find("dasbob").?.sides) |side| try std.testing.expectEqual(core.Side.X, side);
    try std.testing.expect(find("yak") == null);
}

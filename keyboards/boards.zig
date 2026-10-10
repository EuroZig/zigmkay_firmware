const std = @import("std");

/// Firmware selectors are profiles; multiple entries may share physical hardware.
/// Paths are relative to the keyboards package. Wiring remains in each entrypoint.
pub const Entry = struct {
    name: []const u8,
    root_source_file: []const u8,
    default_keymap: []const u8,
};

pub const entries = [_]Entry{
    .{ .name = "clacky_chan", .root_source_file = "my_keyboards/rollercole/clacky_chan.zig", .default_keymap = "my_keyboards/rollercole/shared_keymap_28_1.zig" },
    .{ .name = "clackychan_colemak", .root_source_file = "my_keyboards/janbeelte/clackychan_main.zig", .default_keymap = "my_keyboards/janbeelte/clackychan_colemak_keymap.zig" },
    .{ .name = "keycaprio_colemak_0_4", .root_source_file = "my_keyboards/janbeelte/keycaprio_main_0_4.zig", .default_keymap = "my_keyboards/janbeelte/clackychan_colemak_keymap.zig" },
    .{ .name = "keycaprio_colemak_0_6", .root_source_file = "my_keyboards/janbeelte/keycaprio_main_0_6.zig", .default_keymap = "my_keyboards/janbeelte/keycaprio_colemak_keymap.zig" },
    .{ .name = "keycaprio_us_intl_0_7", .root_source_file = "my_keyboards/janbeelte/keycaprio_main_0_7.zig", .default_keymap = "my_keyboards/janbeelte/keycaprio_us_intl_keymap.zig" },
    .{ .name = "lk1", .root_source_file = "my_keyboards/rollercole/leonardo_keycaprio_0_1.zig", .default_keymap = "my_keyboards/rollercole/shared_keymap_28_1.zig" },
    .{ .name = "lk2", .root_source_file = "my_keyboards/rollercole/leonardo_keycaprio_0_2.zig", .default_keymap = "my_keyboards/rollercole/shared_keymap_28_1.zig" },
    .{ .name = "lk6", .root_source_file = "my_keyboards/rollercole/leonardo_keycaprio_0_6.zig", .default_keymap = "my_keyboards/rollercole/shared_keymap_3x5_2.zig" },
    .{ .name = "lk7", .root_source_file = "my_keyboards/rollercole/leonardo_keycaprio_0_7.zig", .default_keymap = "my_keyboards/rollercole/shared_keymap_3x5_2.zig" },
    .{ .name = "encoder_demo", .root_source_file = "my_keyboards/rollercole/encoder_demo.zig", .default_keymap = "my_keyboards/rollercole/encoder_demo_keymap.zig" },
    .{ .name = "dasbob", .root_source_file = "examples/dasbob/main.zig", .default_keymap = "examples/dasbob/keymap.zig" },
    .{ .name = "tuckytwotimes", .root_source_file = "my_keyboards/rollercole/tuckytwotimes.zig", .default_keymap = "my_keyboards/rollercole/shared_keymap_28_1.zig" },
    .{ .name = "molekula", .root_source_file = "my_keyboards/molekula/main.zig", .default_keymap = "my_keyboards/molekula/keymap.zig" },
};

/// Yak remains an unselected source example, not a supported selector.
pub const unselected_examples = [_][]const u8{"examples/yak/main.zig"};

pub fn find(name: []const u8) ?Entry {
    for (entries) |entry| if (std.mem.eql(u8, name, entry.name)) return entry;
    return null;
}

test "firmware selector names are unique" {
    for (entries, 0..) |entry, index| {
        try std.testing.expectEqualStrings(entry.name, find(entry.name).?.name);
        for (entries[index + 1 ..]) |other| try std.testing.expect(!std.mem.eql(u8, entry.name, other.name));
    }
    try std.testing.expect(find("yak") == null);
    try std.testing.expect(find("unknown") == null);
}

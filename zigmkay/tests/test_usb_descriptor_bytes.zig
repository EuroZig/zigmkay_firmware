// SPDX-License-Identifier: GPL-2.0
// Adapted from zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
const std = @import("std");
const wire = @import("zigmkay").usb_descriptor_bytes;

// Nested align(1) integers reproduce padding in target aggregate constants.
const Word = extern struct { value: u16 align(1) };
const Header = extern struct {
    length: u8 = 9,
    kind: u8 = 2,
    total: Word = .{ .value = 27 },
    interfaces: u8 = 1,
    configuration: u8 = 1,
    string: u8 = 0,
    attributes: u8 = 0x80,
    power: u8 = 250,
};
const Interface = extern struct {
    length: u8 = 9,
    kind: u8 = 4,
    number: u8 = 0,
    alternate: u8 = 0,
    endpoints: u8 = 2,
    triple: [3]u8 = .{ 3, 1, 1 },
    string: u8 = 4,
};
const Hid = extern struct {
    length: u8 = 9,
    kind: u8 = 0x21,
    version: Word = .{ .value = 0x0111 },
    country: u8 = 0,
    count: u8 = 1,
    report: u8 = 0x22,
    report_length: Word = .{ .value = 65 },
};
const Configuration = extern struct { header: Header = .{}, interface: Interface = .{}, hid: Hid = .{} };

test "nested USB descriptors serialize without ABI padding and preserve unaligned words" {
    const bytes = wire.encode(Configuration{});
    try std.testing.expectEqualSlices(u8, &.{
        9, 2,    27,   0, 1, 1, 0,    0x80, 250,
        9, 4,    0,    0, 2, 3, 1,    1,    4,
        9, 0x21, 0x11, 1, 0, 1, 0x22, 65,   0,
    }, &bytes);
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += bytes[offset]) {
        try std.testing.expectEqual(@as(u8, 9), bytes[offset]);
    }
    try std.testing.expectEqual(bytes.len, offset);
}

test "wire bytes decode into persistent runtime fields without aggregate copying" {
    var bytes = wire.encode(Configuration{});
    // Runtime mutation prevents this from becoming another constant-layout test.
    bytes[4] = 3;
    const result = wire.decode(Configuration, &bytes);
    try std.testing.expectEqual(@as(u16, 27), result.header.total.value);
    try std.testing.expectEqual(@as(u8, 3), result.header.interfaces);
    try std.testing.expectEqual(@as(u16, 0x0111), result.hid.version.value);
    try std.testing.expectEqual(@as(u16, 65), result.hid.report_length.value);
}

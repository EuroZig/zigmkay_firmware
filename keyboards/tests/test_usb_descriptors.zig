const std = @import("std");
const descriptors = @import("usb_descriptors");

test "pinned serializer emits reserved keyboard byte before key array" {
    const expected = [_]u8{ 0x95, 8, 0x75, 1, 0x81, 2, 0x95, 1, 0x75, 8, 0x81, 1, 0x05, 7 };
    try std.testing.expect(std.mem.indexOf(u8, descriptors.Keyboard.report_descriptor, &expected) != null);
}

test "pinned serializer emits relative X Y wheel and pan" {
    const xy = [_]u8{ 0x19, 0x30, 0x29, 0x31, 0x15, 0x81, 0x25, 0x7f, 0x95, 2, 0x75, 8, 0x81, 6 };
    try std.testing.expect(std.mem.indexOf(u8, descriptors.Mouse.report_descriptor, &xy) != null);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, descriptors.Mouse.report_descriptor, &.{ 0x81, 6 }));
}

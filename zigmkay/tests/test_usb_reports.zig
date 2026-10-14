const std = @import("std");
const reports = @import("zigmkay").usb_reports;

test "boot keyboard serializes modifiers reserved byte and six keys" {
    const report = reports.KeyboardInReport{ .modifiers = 0xff, .keys = .{ 4, 5, 6, 7, 8, 9 } };
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(reports.KeyboardInReport));
    try std.testing.expectEqual(@as(usize, 1), @offsetOf(reports.KeyboardInReport, "reserved"));
    try std.testing.expectEqual(@as(usize, 2), @offsetOf(reports.KeyboardInReport, "keys"));
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0, 4, 5, 6, 7, 8, 9 }, std.mem.asBytes(&report));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0, 0, 0, 0 }, std.mem.asBytes(&reports.KeyboardInReport.empty));
}

test "consumer report is two little endian bytes on firmware targets" {
    // MicroZig sends the native extern bytes directly; RP2040 is little endian.
    try std.testing.expectEqual(std.builtin.Endian.little, @import("builtin").target.cpu.arch.endian());
    const report = reports.ConsumerInReport{ .button = 0x0238 };
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(reports.ConsumerInReport));
    try std.testing.expectEqualSlices(u8, &.{ 0x38, 0x02 }, std.mem.asBytes(&report));
}

test "mouse report has five exact bytes with signed displacement" {
    const report = reports.MouseInReport{ .buttons = 0x15, .x = -127, .y = 127, .wheel = -1, .pan = -2 };
    try std.testing.expectEqual(@as(usize, 5), @sizeOf(reports.MouseInReport));
    try std.testing.expectEqualSlices(u8, &.{ 0x15, 0x81, 0x7f, 0xff, 0xfe }, std.mem.asBytes(&report));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0 }, std.mem.asBytes(&reports.MouseInReport.empty));
}

test "keyboard output LEDs retain the existing one byte shape" {
    const report = reports.KeyboardOutReport{ .num_lock = true, .caps_lock = false, .scroll_lock = true };
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(reports.KeyboardOutReport));
    try std.testing.expectEqual(@as(u8, 5), @as(u8, @bitCast(report)));
}

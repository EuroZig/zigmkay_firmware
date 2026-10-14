// SPDX-License-Identifier: GPL-2.0
// Retained from conlorz/zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f,
// tests/test_observer_inputs.zig.
const std = @import("std");
const zigmkay = @import("zigmkay");
const core = zigmkay.core;
const protocol = zigmkay.device_protocol;
const dimensions = core.KeymapDimensions{ .key_count = 3, .layer_count = 1 };
const keymap = [_][3]?core.KeyDef{.{
    .{ .tap_only = .{ .key_press = .{ .tap_keycode = 4 } } },
    .{ .tap_only = .{ .key_press = .{ .tap_keycode = 5 } } },
    .none,
}};
const sides = [_]core.Side{ .L, .L, .L };
const combos = [_]core.Combo2Def{.{ .key_indexes = .{ 0, 1 }, .timeout = .{ .ms = 40 }, .layer = 0, .key_def = .{ .tap_only = .{ .key_press = .{ .tap_keycode = 6 } } } }};
const Processor = zigmkay.processing.CreateObservedProcessorType(&dimensions, &keymap, &sides, &combos, &.{}, &.{}, null);
const Capture = struct {
    messages: [6]protocol.Message = undefined,
    count: usize = 0,
    fn write(context: *anyopaque, message: protocol.Message) bool {
        const self: *Capture = @ptrCast(@alignCast(context));
        self.messages[self.count] = message;
        self.count += 1;
        return true;
    }
};

test "combo components and disabled keys are observed once despite processing retries" {
    var input = core.MatrixStateChangeQueue.Create();
    var encoders = core.EncoderEventQueue.Create();
    var output = core.OutputCommandQueue.Create();
    var capture = Capture{};
    var processor = Processor{ .input_matrix_changes = &input, .encoder_event_changes = &encoders, .output_usb_commands = &output, .observer = .{ .sink = .{ .context = &capture, .write = Capture.write } } };
    try input.enqueue(.{ .pressed = true, .key_index = 0, .time = core.TimeSinceBoot.from_absolute_us(0) });
    try processor.Process(core.TimeSinceBoot.from_absolute_us(0));
    try processor.Process(core.TimeSinceBoot.from_absolute_us(1_000));
    try std.testing.expectEqual(@as(usize, 1), capture.count);
    try input.enqueue(.{ .pressed = true, .key_index = 1, .time = core.TimeSinceBoot.from_absolute_us(2_000) });
    try processor.Process(core.TimeSinceBoot.from_absolute_us(2_000));
    try std.testing.expectEqual(core.OutputCommand{ .KeyCodePress = 6 }, output.dequeue().?);
    try input.enqueue(.{ .pressed = true, .key_index = 2, .time = core.TimeSinceBoot.from_absolute_us(3_000) });
    try processor.Process(core.TimeSinceBoot.from_absolute_us(3_000));
    for (0..3) |index| {
        try input.enqueue(.{ .pressed = false, .key_index = @intCast(index), .time = core.TimeSinceBoot.from_absolute_us(4_000) });
    }
    try processor.Process(core.TimeSinceBoot.from_absolute_us(4_000));
    try processor.Process(core.TimeSinceBoot.from_absolute_us(5_000));
    try std.testing.expectEqual(@as(usize, 6), capture.count);
    for (capture.messages, 0..) |message, i| {
        try std.testing.expectEqual(@as(u16, @intCast(i)), message.sequence);
        try std.testing.expectEqual(@as(core.KeyIndex, @intCast(i % 3)), message.event.key.key_index);
        try std.testing.expectEqual(i < 3, message.event.key.pressed);
    }
    try std.testing.expectEqual(core.OutputCommand{ .KeyCodeRelease = 6 }, output.dequeue().?);
    try std.testing.expectEqual(@as(usize, 0), output.Count());
}

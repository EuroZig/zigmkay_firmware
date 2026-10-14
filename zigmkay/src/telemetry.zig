//! Ported from the MIT-licensed zigmkay_firmware reference at
//! 3ee4135d308f18f15cc51b1d73e33e1b36bf517f; retained offline observation semantics.
//! Optional observation only: no USB scheduling or shared keyboard output queue.
const protocol = @import("device_protocol.zig");
pub const Message = protocol.Message;
pub const Event = protocol.Event;
pub const Signal = protocol.Signal;
pub const SignalKind = protocol.SignalKind;
pub const Sink = struct {
    context: *anyopaque,
    /// Must be nonblocking; false indicates a dropped event.
    write: *const fn (*anyopaque, Message) bool,
};
pub const SignalSink = struct {
    context: *anyopaque,
    write: *const fn (*anyopaque, protocol.Signal) void,
};

pub const Observer = struct {
    sink: ?Sink = null,
    next_sequence: u16 = 0,
    dropped_events: u32 = 0,
    state: protocol.Snapshot = .{},

    pub fn emit(self: *Observer, event: Event) void {
        switch (event) {
            .key => |key| {
                const mask = @as(u8, 1) << @as(u3, @intCast(key.key_index % 8));
                if (key.pressed) self.state.pressed[key.key_index / 8] |= mask else self.state.pressed[key.key_index / 8] &= ~mask;
            },
            .layers => |layers| {
                self.state.active_layers = layers.active_layers;
                self.state.highest_layer = layers.highest_layer;
                self.state.modifiers = layers.modifiers;
            },
        }
        const sink = self.sink orelse return;
        const message = Message{ .sequence = self.next_sequence, .event = event };
        self.next_sequence +%= 1;
        if (!sink.write(sink.context, message)) self.dropped_events +%= 1;
    }
};

test "disabled observer retains physical state without traffic" {
    const std = @import("std");
    var observer = Observer{};
    observer.emit(.{ .key = .{ .key_index = 0, .pressed = true, .layer = 0, .modifiers = .{} } });
    try std.testing.expectEqual(@as(u8, 1), observer.state.pressed[0]);
    try std.testing.expectEqual(@as(u16, 0), observer.next_sequence);
    try std.testing.expectEqual(@as(u32, 0), observer.dropped_events);
}

// SPDX-License-Identifier: GPL-2.0
// Adapted from zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f,
// zigmkay/tests/test_usb_recovery.zig; diagnostic-only fixture excluded.
const std = @import("std");
const firmware = @import("zigmkay");
const ep0 = firmware.usb_ep0;
const requests = firmware.usb_requests;

const Device = struct {
    const Endpoint = enum { ep0 };
    packets: [16][64]u8 = undefined,
    lengths: [16]usize = @splat(0),
    writes: usize = 0,
    listens: usize = 0,
    listen_length: usize = 0,
    incoming: []const u8 = &.{},
    pub fn ep_writev(self: *@This(), _: Endpoint, slices: []const []const u8) usize {
        const length = @min(64, slices[0].len);
        @memcpy(self.packets[self.writes][0..length], slices[0][0..length]);
        self.lengths[self.writes] = length;
        self.writes += 1;
        return length;
    }
    pub fn ep_ack(self: *@This(), endpoint: Endpoint) void {
        _ = self.ep_writev(endpoint, &.{&.{}});
    }
    pub fn ep_listen(self: *@This(), _: Endpoint, length: usize) void {
        self.listens += 1;
        self.listen_length = length;
    }
    pub fn ep_readv(self: *@This(), _: Endpoint, slices: []const []u8) usize {
        @memcpy(slices[0][0..self.incoming.len], self.incoming);
        return self.incoming.len;
    }
};

const Capture = struct {
    var rejects: usize = 0;
    var configurations: usize = 0;
    var configuration: u16 = 0;
    var address: u7 = 0;
    var halted: [256]bool = @splat(false);
    var vendor: [32]u8 = @splat(0);
    var contract: ?*requests.Device = null;
    fn reject() void {
        rejects += 1;
    }
    fn accept(bytes: []const u8) bool {
        return Capture.contract.?.receiveOutput(bytes);
    }
    fn configure(number: u16) void {
        configurations += 1;
        configuration = number;
    }
    fn setAddress(value: u7) void {
        address = value;
    }
    fn halt(endpoint: u8, value: ?bool) bool {
        if (value) |change| halted[endpoint] = change;
        return halted[endpoint];
    }
    fn output(bytes: []const u8) void {
        @memcpy(&vendor, bytes);
    }
};

fn setup(raw: u8, request: u8, value: u16, index: u16, length: u16) ep0.Setup {
    return .{ .request_type = raw, .request = request, .value = value, .index = index, .length = length };
}
fn contract() requests.Device {
    return .{
        .device_descriptor = &.{ 18, 1 },
        .configuration_descriptor = &.{ 9, 2 },
        .strings = &.{ &.{ 4, 3, 9, 4 }, &.{ 4, 3, 'A', 0 } },
        .hid_descriptors = &(@as([4][9]u8, @splat(@splat(0)))),
        .report_descriptors = &.{ &.{1}, &.{2}, &.{3}, &.{4} },
        .endpoints = &.{ 1, 0x82, 3, 0x84, 5, 0x86, 7, 0x88 },
        .hooks = .{ .configure = Capture.configure, .address = Capture.setAddress, .halt = Capture.halt, .vendor_output = Capture.output },
    };
}

test "production EP0 splits descriptor data and consumes one DATA1 status OUT" {
    var transfer = ep0.Transfer{};
    var device = Device{};
    var bytes: [146]u8 = undefined;
    for (&bytes, 0..) |*byte, i| byte.* = @intCast(i);
    transfer.setup(&device, setup(0x80, 6, 0x200, 0, 255), .{ .input = &bytes }, Capture.reject);
    for (0..3) |_| try std.testing.expect(!transfer.inComplete(&device));
    try std.testing.expectEqualSlices(usize, &.{ 64, 64, 18 }, device.lengths[0..device.writes]);
    try std.testing.expectEqualSlices(u8, bytes[64..128], device.packets[1][0..64]);
    try std.testing.expectEqual(@as(usize, 1), device.listens);
    try std.testing.expectEqual(@as(usize, 0), device.listen_length);
    transfer.outComplete(&device, Capture.accept, Capture.reject);
    try std.testing.expectEqual(ep0.Phase.idle, transfer.phase);
    transfer.outComplete(&device, Capture.accept, Capture.reject);
    try std.testing.expectEqual(@as(usize, 1), device.listens);
}

test "production EP0 distinguishes exact host limit from short packet multiple and empty response" {
    const bytes: [64]u8 = @splat(7);
    for ([_]struct { length: u16, expected: []const usize }{
        .{ .length = 9, .expected = &.{9} },
        .{ .length = 64, .expected = &.{64} },
        .{ .length = 65, .expected = &.{ 64, 0 } },
    }) |case| {
        var transfer = ep0.Transfer{};
        var device = Device{};
        transfer.setup(&device, setup(0x80, 6, 0x200, 0, case.length), .{ .input = &bytes }, Capture.reject);
        while (transfer.phase == .input) _ = transfer.inComplete(&device);
        try std.testing.expectEqualSlices(usize, case.expected, device.lengths[0..device.writes]);
        try std.testing.expectEqual(@as(usize, 1), device.listens);
    }
    var transfer = ep0.Transfer{};
    var device = Device{};
    transfer.setup(&device, setup(0x80, 6, 0x200, 0, 1), .{ .input = &.{} }, Capture.reject);
    try std.testing.expectEqual(@as(usize, 0), device.lengths[0]);
    _ = transfer.inComplete(&device);
    try std.testing.expectEqual(ep0.Phase.status_out, transfer.phase);
}

test "address commit cancellation reset and repeated configuration cross the request contract" {
    var state = contract();
    Capture.address = 0;
    Capture.configurations = 0;
    try std.testing.expectEqual(ep0.Reply.ack, state.setup(setup(0, 5, 12, 0, 0)));
    try std.testing.expectEqual(@as(u7, 0), Capture.address);
    _ = state.setup(setup(0x80, 6, 0x100, 0, 18));
    state.statusComplete();
    try std.testing.expectEqual(@as(u7, 0), Capture.address);
    _ = state.setup(setup(0, 5, 12, 0, 0));
    state.statusComplete();
    try std.testing.expectEqual(@as(u7, 12), Capture.address);
    for ([_]u16{ 1, 1, 0, 1 }) |number| {
        try std.testing.expectEqual(ep0.Reply.ack, state.setup(setup(0, 9, number, 0, 0)));
        const reply = state.setup(setup(0x80, 8, 0, 0, 1));
        try std.testing.expectEqual(@as(u8, @intCast(number)), reply.input[0]);
    }
    try std.testing.expectEqual(@as(usize, 4), Capture.configurations);
    state.idle[0] = 3;
    state.protocol = 0;
    state.reset();
    try std.testing.expectEqual(@as(u8, 0), state.configuration);
    try std.testing.expectEqual(@as(u7, 0), state.address);
    try std.testing.expectEqual(@as(u8, 1), state.protocol);
    try std.testing.expectEqual(@as(u8, 0), state.idle[0]);
}

test "keyboard boot report idle protocol LED output and vendor output share production requests" {
    var state = contract();
    state.address = 12;
    _ = state.setup(setup(0, 9, 1, 0, 0));
    Capture.contract = &state;
    defer Capture.contract = null;
    var transfer = ep0.Transfer{};
    var device = Device{};
    const led_setup = setup(0x21, 9, 0x200, 0, 1);
    transfer.setup(&device, led_setup, state.setup(led_setup), Capture.reject);
    try std.testing.expectEqual(@as(usize, 0), device.writes);
    device.incoming = &.{0x12};
    transfer.outComplete(&device, Capture.accept, Capture.reject);
    try std.testing.expectEqual(@as(u8, 0x12), state.output[0][0]);
    try std.testing.expectEqual(ep0.Phase.status_in, transfer.phase);
    try std.testing.expect(transfer.inComplete(&device));
    try std.testing.expectEqual(@as(u8, 0x12), state.setup(setup(0xa1, 1, 0x200, 0, 1)).input[0]);
    const input = [_]u8{ 2, 0, 4, 5, 0, 0, 0, 0 };
    state.recordInput(0, &input);
    for ([_]u16{ 0, 1 }) |mode| {
        _ = state.setup(setup(0x21, 11, mode, 0, 0));
        try std.testing.expectEqual(@as(u8, @intCast(mode)), state.setup(setup(0xa1, 3, 0, 0, 1)).input[0]);
        try std.testing.expectEqualSlices(u8, &input, state.setup(setup(0xa1, 1, 0x100, 0, 8)).input);
    }
    _ = state.setup(setup(0x21, 10, 0x0300, 0, 0));
    try std.testing.expectEqual(@as(u8, 3), state.setup(setup(0xa1, 2, 0, 0, 1)).input[0]);
    const bytes: [32]u8 = @splat(0x27);
    try std.testing.expect(state.interruptOutput(3, &bytes));
    try std.testing.expectEqualSlices(u8, &bytes, &Capture.vendor);
    const output_setup = setup(0x21, 9, 0x200, 3, 32);
    transfer.setup(&device, output_setup, state.setup(output_setup), Capture.reject);
    device.incoming = bytes[0..31];
    transfer.outComplete(&device, Capture.accept, Capture.reject);
    try std.testing.expectEqual(ep0.Phase.stalled, transfer.phase);
    transfer.setup(&device, output_setup, state.setup(output_setup), Capture.reject);
    device.incoming = &bytes;
    transfer.outComplete(&device, Capture.accept, Capture.reject);
    try std.testing.expectEqual(ep0.Phase.status_in, transfer.phase);
    try std.testing.expectEqualSlices(u8, &bytes, state.setup(setup(0xa1, 1, 0x200, 3, 32)).input);
}

test "unsupported malformed and unconfigured requests explicitly reject and halt is per endpoint" {
    var state = contract();
    try std.testing.expectEqual(ep0.Reply.reject, state.setup(setup(0x81, 6, 0x2200, 0, 64)));
    state.address = 12;
    _ = state.setup(setup(0, 9, 1, 0, 0));
    for ([_]ep0.Setup{
        setup(0, 9, 2, 0, 0),         setup(0, 9, 1, 1, 0),         setup(0, 9, 1, 0, 1),
        setup(0x80, 6, 0x600, 0, 10), setup(0x80, 6, 0x201, 0, 64), setup(0x80, 6, 0x301, 0x411, 32),
        setup(0x21, 9, 0x201, 3, 32), setup(0x21, 9, 0x200, 3, 33), setup(0x21, 9, 0x300, 3, 32),
        setup(0x21, 9, 0x200, 1, 1),  setup(0x21, 11, 0, 1, 0),     setup(0x21, 11, 2, 0, 0),
        setup(0x21, 10, 1, 0, 0),     setup(0x81, 10, 0, 0x100, 1), setup(0x01, 11, 1, 0, 0),
        setup(0x02, 3, 0, 0, 0),      setup(0x02, 3, 0, 0x89, 0),   setup(0x40, 0xff, 0, 0, 0),
    }) |packet| try std.testing.expectEqual(ep0.Reply.reject, state.setup(packet));
    try std.testing.expectEqual(ep0.Reply.ack, state.setup(setup(0x02, 3, 0, 0x82, 0)));
    try std.testing.expectEqual(@as(u8, 1), state.setup(setup(0x82, 0, 0, 0x82, 2)).input[0]);
    _ = state.setup(setup(0x02, 1, 0, 0x82, 0));
    try std.testing.expectEqual(@as(u8, 0), state.setup(setup(0x82, 0, 0, 0x82, 2)).input[0]);
    var transfer = ep0.Transfer{};
    var device = Device{};
    Capture.rejects = 0;
    transfer.setup(&device, setup(0x40, 255, 0, 0, 0), .reject, Capture.reject);
    try std.testing.expectEqual(@as(usize, 1), Capture.rejects);
    try std.testing.expectEqual(@as(usize, 0), device.writes);
    transfer.setup(&device, setup(0x80, 6, 0x100, 0, 18), .{ .input = state.device_descriptor }, Capture.reject);
    transfer.reset();
    try std.testing.expect(!transfer.inComplete(&device));
    try std.testing.expectEqual(@as(usize, 0), device.listens);
}

test "boot report has reserved byte and rollover preserves every release" {
    var state = firmware.usb_reports.KeyboardState{};
    state.modifiers = 0x82;
    for (4..11) |usage| state.press(@intCast(usage));
    const rollover = state.report();
    try std.testing.expectEqualSlices(u8, &.{ 0x82, 0, 1, 1, 1, 1, 1, 1 }, std.mem.asBytes(&rollover));
    state.release(7);
    const normal = state.report();
    try std.testing.expectEqualSlices(u8, &.{ 0x82, 0, 4, 5, 6, 8, 9, 10 }, std.mem.asBytes(&normal));
    for (4..11) |usage| state.release(@intCast(usage));
    // Internal custom sentinels are not keyboard-page usages.
    state.press(0xfe);
    try std.testing.expectEqualSlices(u8, &.{ 0x82, 0, 0, 0, 0, 0, 0, 0 }, std.mem.asBytes(&state.report()));
}

const FakeReports = struct {
    pub const MouseInReport = extern struct {
        buttons: u8 = 0,
        x: i8 = 0,
        y: i8 = 0,
        wheel: i8 = 0,
        pan: i8 = 0,
        pub const empty: @This() = .{};
    };
    pub const ConsumerInReport = extern struct { button: u16 };
    pub const RawHidReport = [32]u8;
    var ready: bool = false;
    var reports: [8]firmware.usb_reports.Keyboard = undefined;
    var count: usize = 0;
    var connected: bool = true;
    var generation: u32 = 0;
    var secondary_ready: bool = true;
    var idle_enabled: bool = false;
    var idle_count: usize = 0;
    pub fn poll() void {}
    pub fn configured() bool {
        return connected;
    }
    pub fn configuration_generation() u32 {
        return generation;
    }
    pub fn idle(pending: [4]bool) void {
        if (!pending[0] and idle_enabled and ready) {
            idle_count += 1;
            ready = false;
        }
    }
    pub fn send_keyboard_report(report: *const firmware.usb_reports.Keyboard) bool {
        if (!ready) return false;
        reports[count] = report.*;
        count += 1;
        ready = false;
        return true;
    }
    pub fn send_consumer_report(_: *const ConsumerInReport) bool {
        return secondary_ready;
    }
    pub fn send_mouse_report(_: *const MouseInReport) bool {
        return secondary_ready;
    }
    pub fn send_raw_report(_: *const RawHidReport) bool {
        return false;
    }
};
const FakePlatform = struct {
    pub const rom = struct {
        pub fn reset_to_usb_boot() void {}
    };
};

test "production executor retains ordered press modifier and release across endpoint backpressure" {
    const Executor = firmware.usb.Executor(FakeReports, FakePlatform);
    Executor.reset();
    FakeReports.ready = false;
    FakeReports.count = 0;
    FakeReports.connected = true;
    FakeReports.generation = 0;
    FakeReports.secondary_ready = true;
    FakeReports.idle_enabled = true;
    const executor = Executor{};
    var queue = firmware.core.OutputCommandQueue.Create();
    try queue.queue.enqueue(.{ .KeyCodePress = 4 });
    try queue.queue.enqueue(.{ .ModifiersChanged = .{ .left_shift = true } });
    try queue.queue.enqueue(.{ .KeyCodeRelease = 4 });
    for (1..4) |tick| try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(tick * 10001));
    try std.testing.expectEqual(@as(usize, 0), FakeReports.count);
    try std.testing.expectEqual(@as(usize, 2), queue.Count());
    for (4..7) |tick| {
        FakeReports.ready = true;
        try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(tick * 10001));
    }
    try std.testing.expectEqual(@as(usize, 3), FakeReports.count);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 4, 0, 0, 0, 0, 0 }, std.mem.asBytes(&FakeReports.reports[0]));
    try std.testing.expectEqualSlices(u8, &.{ 2, 0, 4, 0, 0, 0, 0, 0 }, std.mem.asBytes(&FakeReports.reports[1]));
    try std.testing.expectEqualSlices(u8, &.{ 2, 0, 0, 0, 0, 0, 0, 0 }, std.mem.asBytes(&FakeReports.reports[2]));
    try std.testing.expectEqual(@as(usize, 0), queue.Count());
    try queue.send_raw_hid_signal(1, &.{1});
    try queue.queue.enqueue(.{ .ModifiersChanged = .{} });
    try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(70007));
    FakeReports.ready = true;
    try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(80008));
    try std.testing.expectEqual(@as(usize, 4), FakeReports.count);
    FakeReports.idle_enabled = false;
}

test "secondary endpoint stalls do not hold a keyboard release and reconnect restores held state" {
    const Executor = firmware.usb.Executor(FakeReports, FakePlatform);
    Executor.reset();
    FakeReports.count = 0;
    FakeReports.connected = true;
    FakeReports.generation = 0;
    FakeReports.secondary_ready = false;
    FakeReports.ready = true;
    const executor = Executor{};
    var queue = firmware.core.OutputCommandQueue.Create();
    try queue.queue.enqueue(.{ .KeyCodePress = 4 });
    try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(10001));
    try queue.queue.enqueue(.{ .ConsumerKeyReleased = .NextTrack });
    try queue.queue.enqueue(.{ .MouseCommandPressed = .LeftButton });
    try queue.queue.enqueue(.{ .KeyCodeRelease = 4 });
    for (2..5) |tick| {
        FakeReports.ready = true;
        try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(tick * 10001));
    }
    try std.testing.expectEqual(@as(usize, 2), FakeReports.count);
    try std.testing.expectEqual(@as(u8, 0), FakeReports.reports[1].keys[0]);
    FakeReports.idle_enabled = true;
    FakeReports.idle_count = 0;
    FakeReports.ready = true;
    try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(40004));
    try std.testing.expectEqual(@as(usize, 1), FakeReports.idle_count);
    FakeReports.idle_enabled = false;
    // During disconnect a complete tap is consumed; a held key survives.
    FakeReports.connected = false;
    FakeReports.generation = 1;
    try queue.queue.enqueue(.{ .KeyCodePress = 5 });
    try queue.queue.enqueue(.{ .KeyCodeRelease = 5 });
    try queue.queue.enqueue(.{ .KeyCodePress = 6 });
    try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(40005));
    try std.testing.expectEqual(@as(usize, 0), queue.Count());
    try std.testing.expectEqual(@as(usize, 2), FakeReports.count);
    FakeReports.connected = true;
    FakeReports.generation = 2;
    FakeReports.ready = true;
    try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(50005));
    try std.testing.expectEqual(@as(usize, 3), FakeReports.count);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 6, 0, 0, 0, 0, 0 }, std.mem.asBytes(&FakeReports.reports[2]));
    FakeReports.secondary_ready = true;
}

test "secondary overflow remains bounded and keyboard commands continue" {
    const Executor = firmware.usb.Executor(FakeReports, FakePlatform);
    Executor.reset();
    FakeReports.count = 0;
    FakeReports.connected = true;
    FakeReports.generation = 0;
    FakeReports.secondary_ready = false;
    const executor = Executor{};
    var queue = firmware.core.OutputCommandQueue.Create();
    for (1..35) |tick| {
        try queue.queue.enqueue(.{ .MouseCommandPressed = .WheelUp });
        try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(tick * 10001));
    }
    try std.testing.expect(Executor.secondary_overflows > 0);
    try queue.queue.enqueue(.{ .KeyCodePress = 4 });
    FakeReports.ready = true;
    try executor.HouseKeepAndProcessCommands(&queue, firmware.core.TimeSinceBoot.from_absolute_us(350035));
    try std.testing.expectEqual(@as(usize, 1), FakeReports.count);
    FakeReports.secondary_ready = true;
}

test "idle timing is in four millisecond units and zero suppresses repeats" {
    var state = contract();
    try std.testing.expect(!state.idleDue(0, 99999, 0));
    state.idle[0] = 1;
    try std.testing.expect(!state.idleDue(0, 103, 100));
    try std.testing.expect(state.idleDue(0, 104, 100));
    try std.testing.expect(!state.idleDue(0, 50, 100));
}

test "RP2040 setup resets both DATA1 starts after odd or even packet histories and W1C clears requested abort flags" {
    const buffer = firmware.usb_buffer_control;
    for (0..4) |history| {
        var control: u32 = buffer.available | buffer.full | buffer.stall;
        for (0..history) |_| control ^= buffer.pid;
        control = buffer.prepareSetup(control);
        try std.testing.expectEqual(@as(u32, 0), control & (buffer.available | buffer.full | buffer.stall | buffer.pid));
        control ^= buffer.pid; // Production HAL's write/listen transition.
        try std.testing.expectEqual(buffer.pid, control & buffer.pid);
    }
    var done: u32 = 0b1111;
    done &= ~buffer.abortDoneAck(0b0011);
    try std.testing.expectEqual(@as(u32, 0b1100), done);
}

const Ownership = struct {
    owned: u32 = 3,
    chip: u4 = 2,
    clock: u64 = 0,
    step: u64 = 100,
    completed: u32 = 3,
    aborted: u32 = 0,
    pub fn active(self: *@This(), mask: u32) u32 {
        return self.owned & mask;
    }
    pub fn revision(self: *@This()) u4 {
        return self.chip;
    }
    pub fn abort(self: *@This(), mask: u32) void {
        self.aborted = mask;
    }
    pub fn done(self: *@This()) u32 {
        return self.completed;
    }
    pub fn now(self: *@This()) u64 {
        self.clock += self.step;
        return self.clock;
    }
};
test "hardware buffer revocation rejects early chips and bounds stalled peripherals and clocks" {
    var owner = Ownership{};
    try firmware.usb_buffer_control.revoke(&owner, 1);
    try std.testing.expectEqual(@as(u32, 1), owner.aborted);
    owner = .{ .chip = 1 };
    try std.testing.expectError(error.UnsupportedChipRevision, firmware.usb_buffer_control.revoke(&owner, 3));
    try std.testing.expectEqual(@as(u32, 0), owner.aborted);
    owner.owned = 0;
    try firmware.usb_buffer_control.revoke(&owner, 3);
    owner = .{ .completed = 0, .step = 500 };
    try std.testing.expectError(error.AbortTimeout, firmware.usb_buffer_control.revoke(&owner, 3));
    owner = .{ .completed = 0, .step = 0 };
    try std.testing.expectError(error.AbortTimeout, firmware.usb_buffer_control.revoke(&owner, 3));
}

// SPDX-License-Identifier: GPL-2.0
// Adapted from zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
const std = @import("std");
const core = @import("core.zig");
const microzig = @import("microzig");
const rp2xxx = @import("microzig").hal;

const usb_if = @import("usb_if.zig");
const time = rp2xxx.time;

pub fn CreateAndInitUsbCommandExecutor() UsbCommandExecutor {
    usb_if.init();
    UsbCommandExecutor.reset();
    return UsbCommandExecutor{};
}

pub const UsbCommandExecutor = Executor(usb_if, rp2xxx);

/// The queue/report production boundary is shared with host regressions.
pub fn Executor(comptime Interface: type, comptime Platform: type) type {
    return struct {
        var keyboard_state = @import("usb_reports.zig").KeyboardState{};
        var pending_command: ?core.OutputCommand = null;
        var mouse_report: Interface.MouseInReport = .empty;
        var consumer_report = Interface.ConsumerInReport{ .button = 0 };
        const ConsumerQueue = @import("generic_queue.zig").GenericQueue(Interface.ConsumerInReport, 16);
        const MouseQueue = @import("generic_queue.zig").GenericQueue(Interface.MouseInReport, 16);
        var consumer_queue = ConsumerQueue.Create();
        var mouse_queue = MouseQueue.Create();
        var seen_generation: u32 = 0;
        var resync_pending = false;
        pub var secondary_overflows: u32 = 0;
        var prev_action_time: core.TimeSinceBoot = core.TimeSinceBoot.from_absolute_us(0);

        // Time to wait between USB polls in microseconds.
        const next_tick_delay: u64 = 10000;
        pub fn reset() void {
            keyboard_state = .{};
            pending_command = null;
            mouse_report = .empty;
            consumer_report = .{ .button = 0 };
            consumer_queue = ConsumerQueue.Create();
            mouse_queue = MouseQueue.Create();
            seen_generation = 0;
            resync_pending = false;
            secondary_overflows = 0;
            prev_action_time = core.TimeSinceBoot.from_absolute_us(0);
        }
        pub fn HouseKeepAndProcessCommands(self: *const @This(), output_command_queue: *core.OutputCommandQueue, current_time: core.TimeSinceBoot) !void {
            _ = self;

            Interface.poll(); // Process pending USB events
            const connected = if (@hasDecl(Interface, "configured")) Interface.configured() else true;
            if (@hasDecl(Interface, "configuration_generation")) {
                const generation = Interface.configuration_generation();
                if (generation != seen_generation) {
                    seen_generation = generation;
                    consumer_queue = ConsumerQueue.Create();
                    mouse_queue = MouseQueue.Create();
                    resync_pending = true;
                    if (connected) {
                        try consumer_queue.enqueue(consumer_report);
                        try mouse_queue.enqueue(mouse_report);
                    }
                }
            }
            if (connected and resync_pending) {
                const report = keyboard_state.report();
                if (Interface.send_keyboard_report(&report)) resync_pending = false;
            }

            const diff_us = current_time.time_since_boot_us - prev_action_time.time_since_boot_us;

            var processed = false;
            // While disconnected consume state transitions without replaying
            // obsolete taps on reconnection. Physical held state is restored
            // once the new configuration's endpoints are ready.
            while (!connected or (!processed and diff_us > next_tick_delay)) {
                processed = true;
                if (pending_command == null) pending_command = output_command_queue.dequeue();
                if (pending_command) |command| {
                    prev_action_time = current_time;
                    var should_send_keyboard_report = false;
                    var sent = true;
                    switch (command) {
                        .KeyCodePress => |keycode| {
                            should_send_keyboard_report = true;

                            keyboard_state.press(keycode);
                        },
                        .KeyCodeRelease => |keycode| {
                            should_send_keyboard_report = true;
                            keyboard_state.release(keycode);
                        },
                        .ModifiersChanged => |modifiers| {
                            should_send_keyboard_report = true;
                            keyboard_state.modifiers = modifiers.toByte();
                        },
                        .ActivateBootMode => {
                            Platform.rom.reset_to_usb_boot();
                        },
                        .RawHidSignal => |sig| {
                            var report: Interface.RawHidReport = @splat(0);
                            report[0] = sig.signal_id;
                            @memcpy(report[1 .. 1 + sig.len], sig.data[0..sig.len]);
                            // Legacy optional signals must never block typing when
                            // the companion does not poll its vendor collection.
                            _ = Interface.send_raw_report(&report);
                        },
                        .ConsumerKeyPressed => |key| {
                            consumer_report = .{ .button = @backingInt(key) };
                            if (connected) enqueueConsumer(consumer_report);
                        },
                        .ConsumerKeyReleased => {
                            consumer_report = .{ .button = 0 };
                            if (connected) enqueueConsumer(consumer_report);
                        },
                        .MouseCommandPressed => |action| {
                            update_report(action, true, &mouse_report);
                            if (connected) enqueueMouse(mouse_report);
                            // Clear relative movements after sending
                            mouse_report.wheel = 0;
                            mouse_report.pan = 0;
                        },
                        .MouseCommandReleased => |action| {
                            update_report(action, false, &mouse_report);
                            if (connected) enqueueMouse(mouse_report);

                            // Clear relative movements after sending
                            mouse_report.wheel = 0;
                            mouse_report.pan = 0;
                        },
                    }

                    if (should_send_keyboard_report) {
                        const keyboard_report = keyboard_state.report();
                        sent = !connected or Interface.send_keyboard_report(&keyboard_report);
                    }
                    if (sent) pending_command = null;
                } else break;
            }
            if (connected) {
                if (consumer_queue.peek()) |report| {
                    if (Interface.send_consumer_report(&report)) _ = consumer_queue.dequeue();
                }
                if (mouse_queue.peek()) |report| {
                    if (Interface.send_mouse_report(&report)) _ = mouse_queue.dequeue();
                }
            }
            if (@hasDecl(Interface, "idle")) Interface.idle(.{
                resync_pending or pending_command != null or output_command_queue.has_events(),
                consumer_queue.Count() != 0,
                mouse_queue.Count() != 0,
                false,
            });
        }

        fn enqueueConsumer(report: Interface.ConsumerInReport) void {
            consumer_queue.enqueue(report) catch {
                secondary_overflows +%= 1;
                consumer_queue = ConsumerQueue.Create();
                consumer_queue.enqueue(.{ .button = 0 }) catch unreachable;
                consumer_queue.enqueue(report) catch unreachable;
            };
        }

        fn enqueueMouse(report: Interface.MouseInReport) void {
            mouse_queue.enqueue(report) catch {
                secondary_overflows +%= 1;
                mouse_queue = MouseQueue.Create();
                mouse_queue.enqueue(.empty) catch unreachable;
                mouse_queue.enqueue(report) catch unreachable;
            };
        }
    };
}

fn update_report(mouse_action: core.MouseAction, pressed: bool, mouse_report: anytype) void {
    switch (mouse_action) {
        .LeftButton => {
            if (pressed) mouse_report.buttons |= 0x01 else mouse_report.buttons &= ~@as(u8, 0x01);
        },
        .RightButton => {
            if (pressed) mouse_report.buttons |= 0x02 else mouse_report.buttons &= ~@as(u8, 0x02);
        },
        .MiddleButton => {
            if (pressed) mouse_report.buttons |= 0x04 else mouse_report.buttons &= ~@as(u8, 0x04);
        },
        .Button4 => {
            if (pressed) mouse_report.buttons |= 0x08 else mouse_report.buttons &= ~@as(u8, 0x08);
        },
        .Button5 => {
            if (pressed) mouse_report.buttons |= 0x10 else mouse_report.buttons &= ~@as(u8, 0x10);
        },
        .WheelUp => {
            if (pressed) mouse_report.wheel = 1;
        },
        .WheelDown => {
            if (pressed) mouse_report.wheel = -1;
        },
        .WheelLeft => {
            if (pressed) mouse_report.pan = -1;
        },
        .WheelRight => {
            if (pressed) mouse_report.pan = 1;
        },
    }
}

// SPDX-License-Identifier: GPL-2.0
//! Adapted from zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
//! Validated Chapter 9 and unnumbered HID request contract.
const ep0 = @import("usb_ep0.zig");

pub const Hooks = struct {
    configure: *const fn (u16) void,
    address: *const fn (u7) void,
    /// null queries halt; a bool changes halt. Only validated endpoints arrive.
    halt: *const fn (u8, ?bool) bool,
    vendor_output: *const fn ([]const u8) void,
    alternate: ?*const fn (u8) void = null,
};

pub const Device = struct {
    device_descriptor: []const u8,
    configuration_descriptor: []const u8,
    strings: []const []const u8,
    hid_descriptors: []const [9]u8,
    report_descriptors: []const []const u8,
    endpoints: []const u8,
    vendor_interface: u8 = 3,
    interface_count: u8 = 5,
    hooks: Hooks,
    address: u7 = 0,
    configuration: u8 = 0,
    pending_address: ?u7 = null,
    pending_output: ?u8 = null,
    protocol: u8 = 1,
    idle: [4]u8 = @splat(0),
    input: [4][32]u8 = @splat(@splat(0)),
    output: [4][32]u8 = @splat(@splat(0)),
    reply_byte: [2]u8 = .{ 0, 0 },
    pub const input_sizes = [4]usize{ 8, 2, 5, 32 };

    pub fn cancel(self: *@This()) void {
        self.pending_address = null;
        self.pending_output = null;
    }

    pub fn reset(self: *@This()) void {
        self.cancel();
        self.address = 0;
        self.configure(0);
    }

    fn configure(self: *@This(), number: u8) void {
        self.hooks.configure(number);
        self.configuration = number;
        self.protocol = 1;
        self.idle = @splat(0);
        self.input = @splat(@splat(0));
        self.output = @splat(@splat(0));
    }

    pub fn statusComplete(self: *@This()) void {
        if (self.pending_address) |address| {
            self.address = address;
            self.hooks.address(address);
            self.pending_address = null;
        }
    }

    fn scalar(self: *@This(), value: u8, length: usize) ep0.Reply {
        self.reply_byte = .{ value, 0 };
        return .{ .input = self.reply_byte[0..length] };
    }

    fn endpointExists(self: *@This(), address: u16) bool {
        if (address == 0 or address == 0x80) return true;
        if (self.configuration == 0) return false;
        for (self.endpoints) |candidate| if (candidate == address) return true;
        return false;
    }

    pub fn setup(self: *@This(), s: ep0.Setup) ep0.Reply {
        self.cancel();
        switch (s.request_type) {
            0x80 => switch (s.request) {
                0 => if (s.value == 0 and s.index == 0 and s.length == 2) return self.scalar(0, 2),
                6 => {
                    const index: u8 = @truncate(s.value);
                    switch (s.value >> 8) {
                        1 => if (index == 0 and s.index == 0) return .{ .input = self.device_descriptor },
                        2 => if (index == 0 and s.index == 0) return .{ .input = self.configuration_descriptor },
                        3 => if (index < self.strings.len and ((index == 0 and s.index == 0) or (index != 0 and s.index == 0x409))) return .{ .input = self.strings[index] },
                        else => {},
                    }
                },
                8 => if (s.value == 0 and s.index == 0 and s.length == 1 and self.address != 0) return self.scalar(self.configuration, 1),
                else => {},
            },
            0x00 => switch (s.request) {
                5 => if (s.value <= 127 and s.index == 0 and s.length == 0 and self.configuration == 0) {
                    self.pending_address = @intCast(s.value);
                    return .ack;
                },
                9 => if (s.value <= 1 and s.index == 0 and s.length == 0 and self.address != 0) {
                    self.configure(@intCast(s.value));
                    return .ack;
                },
                else => {},
            },
            0x82 => if (s.request == 0 and s.value == 0 and s.length == 2 and self.endpointExists(s.index)) {
                return self.scalar(@intFromBool(self.hooks.halt(@intCast(s.index), null)), 2);
            },
            0x02 => if ((s.request == 1 or s.request == 3) and s.value == 0 and s.length == 0 and s.index != 0 and s.index != 0x80 and self.endpointExists(s.index)) {
                _ = self.hooks.halt(@intCast(s.index), s.request == 3);
                return .ack;
            },
            0x81 => if (self.configuration != 0 and s.index < self.interface_count) {
                if (s.request == 0 and s.value == 0 and s.length == 2) return self.scalar(0, 2);
                if (s.request == 10 and s.value == 0 and s.length == 1) return self.scalar(0, 1);
                if (s.request == 6 and s.index < self.hid_descriptors.len) {
                    if (s.value == 0x2100) return .{ .input = &self.hid_descriptors[s.index] };
                    if (s.value == 0x2200) return .{ .input = self.report_descriptors[s.index] };
                }
            },
            0x01 => if (self.configuration != 0 and s.index < self.interface_count and s.request == 11 and s.value == 0 and s.length == 0) {
                if (self.hooks.alternate) |alternate| alternate(@intCast(s.index));
                return .ack;
            },
            0xa1, 0x21 => if (self.configuration != 0 and s.index < self.report_descriptors.len) {
                const index: u8 = @intCast(s.index);
                if (s.request_type == 0xa1) switch (s.request) {
                    1 => if (s.value & 0xff == 0) {
                        if (s.value >> 8 == 1) return .{ .input = self.input[index][0..input_sizes[index]] };
                        if (s.value >> 8 == 2 and (index == 0 or index == self.vendor_interface)) return .{ .input = self.output[index][0..if (index == 0) @as(usize, 1) else 32] };
                    },
                    2 => if (s.value == 0 and s.length == 1) return self.scalar(self.idle[index], 1),
                    3 => if (index == 0 and s.value == 0 and s.length == 1) return self.scalar(self.protocol, 1),
                    else => {},
                } else switch (s.request) {
                    9 => if (s.value == 0x0200 and (index == 0 or index == self.vendor_interface) and s.length == (if (index == 0) @as(u16, 1) else 32)) {
                        self.pending_output = index;
                        return .{ .output = s.length };
                    },
                    10 => if (s.value & 0xff == 0 and s.length == 0) {
                        self.idle[index] = @truncate(s.value >> 8);
                        return .ack;
                    },
                    11 => if (index == 0 and s.value <= 1 and s.length == 0) {
                        self.protocol = @intCast(s.value);
                        return .ack;
                    },
                    else => {},
                }
            },
            else => {},
        }
        return .reject;
    }

    pub fn receiveOutput(self: *@This(), bytes: []const u8) bool {
        const index = self.pending_output orelse return false;
        self.pending_output = null;
        return self.interruptOutput(index, bytes);
    }

    pub fn interruptOutput(self: *@This(), index: u8, bytes: []const u8) bool {
        if (self.configuration == 0 or (index != 0 and index != self.vendor_interface) or bytes.len != (if (index == 0) @as(usize, 1) else 32)) return false;
        @memcpy(self.output[index][0..bytes.len], bytes);
        if (index == self.vendor_interface) self.hooks.vendor_output(bytes);
        return true;
    }

    pub fn recordInput(self: *@This(), index: u8, bytes: []const u8) void {
        @memcpy(self.input[index][0..input_sizes[index]], bytes);
    }

    pub fn idleDue(self: *const @This(), index: usize, now_ms: u64, last_ms: u64) bool {
        const duration = @as(u64, self.idle[index]) * 4;
        return duration != 0 and now_ms -| last_ms >= duration;
    }
};

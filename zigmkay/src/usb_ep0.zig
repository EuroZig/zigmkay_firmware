// SPDX-License-Identifier: GPL-2.0
//! Adapted from zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
//! Control transfer sequencing shared by firmware and hardware-free tests.
pub const Setup = struct { request_type: u8, request: u8, value: u16, index: u16, length: u16 };
pub const Reply = union(enum) { reject, ack, input: []const u8, output: u16 };
pub const Phase = enum { idle, input, output, status_in, status_out, stalled };

pub const Transfer = struct {
    phase: Phase = .idle,
    remaining: []const u8 = &.{},
    terminating_zlp: bool = false,
    output_length: u16 = 0,

    pub fn reset(self: *@This()) void {
        self.* = .{};
    }

    pub fn setup(self: *@This(), device: anytype, packet: Setup, reply: Reply, reject: *const fn () void) void {
        self.reset();
        switch (reply) {
            .reject => self.stall(reject),
            .ack => {
                self.phase = .status_in;
                device.ep_ack(.ep0);
            },
            .output => |length| {
                if (length == 0 or length > 64 or length != packet.length) return self.stall(reject);
                self.phase = .output;
                self.output_length = length;
                device.ep_listen(.ep0, @intCast(length));
            },
            .input => |bytes| {
                if (packet.length == 0) {
                    self.phase = .status_in;
                    device.ep_ack(.ep0);
                    return;
                }
                self.phase = .input;
                self.remaining = bytes[0..@min(bytes.len, packet.length)];
                self.terminating_zlp = bytes.len < packet.length and bytes.len != 0 and bytes.len % 64 == 0;
                self.send(device);
            },
        }
    }

    fn send(self: *@This(), device: anytype) void {
        const sent = device.ep_writev(.ep0, &.{self.remaining});
        self.remaining = self.remaining[sent..];
    }

    /// Returns true only for completion of a status IN. Address changes belong
    /// here, never to the first data IN or an unrelated future completion.
    pub fn inComplete(self: *@This(), device: anytype) bool {
        switch (self.phase) {
            .input => {
                if (self.remaining.len != 0) self.send(device) else if (self.terminating_zlp) {
                    self.terminating_zlp = false;
                    device.ep_ack(.ep0);
                } else {
                    self.phase = .status_out;
                    device.ep_listen(.ep0, 0);
                }
            },
            .status_in => {
                self.phase = .idle;
                return true;
            },
            else => {},
        }
        return false;
    }

    pub fn outComplete(self: *@This(), device: anytype, accept: *const fn ([]const u8) bool, reject: *const fn () void) void {
        if (self.phase != .output and self.phase != .status_out) return;
        var scratch: [64]u8 = undefined;
        const length = device.ep_readv(.ep0, &.{&scratch});
        if (self.phase == .status_out) {
            if (length != 0) return self.stall(reject);
            self.phase = .idle;
        } else if (length == self.output_length and accept(scratch[0..length])) {
            self.phase = .status_in;
            device.ep_ack(.ep0);
        } else self.stall(reject);
    }

    fn stall(self: *@This(), reject: *const fn () void) void {
        self.phase = .stalled;
        reject();
    }
};

//! Ported from the MIT-licensed zigmkay_firmware reference at
//! 3ee4135d308f18f15cc51b1d73e33e1b36bf517f; retained offline observation semantics.
//! Fixed-storage v2 transport. All calls are bounded and never affect typing.
const protocol = @import("device_protocol.zig");
const telemetry = @import("telemetry.zig");

pub const delta_capacity = 16;
pub const Endpoint = struct {
    context: *anyopaque,
    /// Must copy/own the bytes before returning true; false preserves the head.
    send: *const fn (*anyopaque, *const protocol.Report) bool,
};

pub const Transport = struct {
    identity: protocol.Identity,
    state: protocol.Snapshot = .{},
    session: u32 = 0,
    next_sequence: u16 = 0,
    deltas: [delta_capacity]protocol.Report = undefined,
    delta_head: usize = 0,
    delta_count: usize = 0,
    controls: [3]protocol.Report = undefined,
    control_head: usize = 0,
    control_count: usize = 0,
    snapshot_pending: bool = false,
    synchronized: bool = false,
    recovery: ?protocol.RecoveryReason = null,
    pending: ?protocol.Packet = null,
    rejected_controls: u32 = 0,
    dropped_events: u32 = 0,
    bootloader_request: ?u16 = null,
    bootloader_started: ?u64 = null,
    bootloader_acknowledged: ?u64 = null,
    pending_bootloader_started: ?u64 = null,
    last_bootloader_request: u16 = 0,
    clock_us: u64 = 0,

    pub fn init(identity: protocol.Identity) Transport {
        return .{ .identity = identity };
    }

    pub fn sink(self: *Transport) telemetry.Sink {
        return .{ .context = self, .write = write };
    }

    fn write(context: *anyopaque, message: protocol.Message) bool {
        const self: *Transport = @ptrCast(@alignCast(context));
        switch (message.event) {
            .key => |key| {
                const mask = @as(u8, 1) << @as(u3, @intCast(key.key_index % 8));
                if (key.pressed) self.state.pressed[key.key_index / 8] |= mask else self.state.pressed[key.key_index / 8] &= ~mask;
                return self.event(.{ .key = key });
            },
            .layers => |layers| {
                self.state.active_layers = layers.active_layers;
                self.state.highest_layer = layers.highest_layer;
                self.state.modifiers = layers.modifiers;
                return self.event(.{ .layers = layers });
            },
        }
    }

    pub fn signal(self: *Transport, value: protocol.Signal) void {
        _ = self.event(.{ .signal = value });
    }

    pub fn signalSink(self: *Transport) telemetry.SignalSink {
        return .{ .context = self, .write = writeSignal };
    }

    fn writeSignal(context: *anyopaque, value: protocol.Signal) void {
        const self: *Transport = @ptrCast(@alignCast(context));
        self.signal(value);
    }

    fn event(self: *Transport, payload: protocol.Payload) bool {
        if (self.session == 0) return true;
        const sequence = self.next_sequence;
        self.next_sequence +%= 1;
        if (!self.synchronized) return true;
        if (self.delta_count == delta_capacity) {
            self.dropped_events +%= 1;
            self.delta_count = 0;
            self.delta_head = 0;
            self.synchronized = false;
            self.recovery = if (self.snapshot_pending) .snapshot_invalidated else .overflow;
            if (self.snapshot_pending) {
                self.control_count = 0;
                self.control_head = 0;
                self.snapshot_pending = false;
            }
            return false;
        }
        const bytes = protocol.encodePacket(.{ .session = self.session, .sequence = sequence, .payload = payload }, self.identity.dimensions, .device_to_host) catch return false;
        self.deltas[(self.delta_head + self.delta_count) % delta_capacity] = bytes;
        self.delta_count += 1;
        return true;
    }

    /// USB callbacks only validate and replace a one-command mailbox. Hello wins
    /// over snapshots; repeated snapshot floods cannot expand storage or work.
    pub fn receive(self: *Transport, bytes: []const u8) void {
        const packet = protocol.decodePacket(bytes, self.identity.dimensions, .host_to_device) catch {
            self.rejected_controls +%= 1;
            return;
        };
        switch (packet.payload) {
            .hello => {
                self.pending = packet;
                self.pending_bootloader_started = null;
            },
            .snapshot_request, .capabilities_request, .enter_bootloader => {
                if (packet.session != self.session or self.session == 0) {
                    self.rejected_controls +%= 1;
                    return;
                }
                if (self.bootloader_request != null or self.pending != null) {
                    self.rejected_controls +%= 1;
                    return;
                }
                self.pending = packet;
                // USB callbacks use the last main-loop tick; this conservative
                // approximation can predate receipt by up to one loop iteration.
                if (packet.payload == .enter_bootloader) self.pending_bootloader_started = self.clock_us;
            },
            else => self.rejected_controls +%= 1,
        }
    }

    /// Invoke after the processor boundary. Capture precedes all subsequent
    /// deltas, and old deltas are discarded at the coherent snapshot cut.
    pub fn boundary(self: *Transport) void {
        const packet = self.pending orelse return;
        if (packet.payload != .hello and self.control_count != 0) return;
        self.pending = null;
        if (packet.payload == .enter_bootloader and self.pending_bootloader_started != null and self.clock_us -| self.pending_bootloader_started.? >= 100_000) {
            self.pending_bootloader_started = null;
            self.rejected_controls +%= 1;
            return;
        }
        switch (packet.payload) {
            .hello => {
                self.disconnect();
                self.session = packet.nonce;
                const parts = protocol.identityPackets(self.identity, packet.nonce, packet.request) catch unreachable;
                for (parts, 0..) |part, i| self.controls[i] = protocol.encodePacket(part, self.identity.dimensions, .device_to_host) catch unreachable;
                self.control_count = 3;
            },
            .snapshot_request => {
                self.delta_count = 0;
                self.delta_head = 0;
                self.recovery = null;
                const parts = protocol.snapshotPackets(self.state, self.identity.dimensions, self.session, packet.request, self.next_sequence) catch unreachable;
                for (parts, 0..) |part, i| self.controls[i] = protocol.encodePacket(part, self.identity.dimensions, .device_to_host) catch unreachable;
                self.control_head = 0;
                self.control_count = 2;
                self.snapshot_pending = true;
                self.synchronized = true;
            },
            .capabilities_request => self.reply(packet.request, .{ .capabilities = protocol.capability_bootloader }),
            .enter_bootloader => {
                defer self.pending_bootloader_started = null;
                if (packet.request <= self.last_bootloader_request) {
                    self.reply(packet.request, .{ .bootloader_result = .duplicate });
                    self.rejected_controls +%= 1;
                } else {
                    self.last_bootloader_request = packet.request;
                    self.bootloader_request = packet.request;
                    self.bootloader_started = self.pending_bootloader_started;
                    self.bootloader_acknowledged = null;
                    self.reply(packet.request, .{ .bootloader_result = .accepted });
                }
            },
            else => unreachable,
        }
    }

    fn reply(self: *Transport, request: u16, payload: protocol.Payload) void {
        self.controls[0] = protocol.encodePacket(.{ .session = self.session, .request = request, .payload = payload }, self.identity.dimensions, .device_to_host) catch unreachable;
        self.control_head = 0;
        self.control_count = 1;
    }

    /// Main-loop only. Drain for 20 ms after ACK; abandon after 100 ms without one.
    pub fn takeBootloader(self: *Transport, now_us: u64) bool {
        self.clock_us = now_us;
        // A replacement Hello must win even at the ACK drain deadline, before
        // the main loop reaches the processor boundary.
        if (self.pending) |packet| {
            if (packet.payload == .hello) {
                self.bootloader_request = null;
                self.bootloader_started = null;
                self.bootloader_acknowledged = null;
            }
        }
        if (self.pending_bootloader_started) |started| {
            if (now_us -| started >= 100_000 and self.pending != null and self.pending.?.payload == .enter_bootloader) {
                self.pending = null;
                self.pending_bootloader_started = null;
                self.rejected_controls +%= 1;
            }
        }
        if (self.bootloader_request == null) return false;
        if (self.bootloader_started == null) self.bootloader_started = now_us;
        if (self.bootloader_acknowledged == null and now_us -| self.bootloader_started.? >= 100_000) {
            self.bootloader_request = null;
            self.control_count = 0;
            self.control_head = 0;
            return false;
        }
        if (self.bootloader_acknowledged) |accepted| {
            if (now_us -| accepted < 20_000) return false;
            self.disconnect();
            return true;
        }
        return false;
    }

    /// At most one send attempt per tick. No readiness loops or allocations.
    pub fn pump(self: *Transport, endpoint: Endpoint) void {
        if (self.session == 0) return;
        if (self.control_count != 0) {
            if (!endpoint.send(endpoint.context, &self.controls[self.control_head])) return;
            if (self.bootloader_request) |request| {
                const sent = protocol.decodePacket(&self.controls[self.control_head], self.identity.dimensions, .device_to_host) catch unreachable;
                if (sent.session == self.session and sent.request == request) {
                    switch (sent.payload) {
                        .bootloader_result => |result| {
                            if (result == .accepted) self.bootloader_acknowledged = self.clock_us;
                        },
                        else => {},
                    }
                }
            }
            self.control_head += 1;
            self.control_count -= 1;
            if (self.control_count == 0) self.snapshot_pending = false;
        } else if (self.recovery) |reason| {
            const bytes = protocol.encodePacket(.{ .session = self.session, .payload = .{ .recovery = reason } }, self.identity.dimensions, .device_to_host) catch unreachable;
            if (endpoint.send(endpoint.context, &bytes)) self.recovery = null;
        } else if (self.delta_count != 0) {
            if (!endpoint.send(endpoint.context, &self.deltas[self.delta_head])) return;
            self.delta_head = (self.delta_head + 1) % delta_capacity;
            self.delta_count -= 1;
        }
    }

    /// Physical state survives disconnect; queued traffic and tokens do not.
    pub fn disconnect(self: *Transport) void {
        self.session = 0;
        self.next_sequence = 0;
        self.delta_count = 0;
        self.delta_head = 0;
        self.control_count = 0;
        self.control_head = 0;
        self.snapshot_pending = false;
        self.synchronized = false;
        self.recovery = null;
        self.pending = null;
        self.pending_bootloader_started = null;
        self.bootloader_request = null;
        self.bootloader_started = null;
        self.bootloader_acknowledged = null;
        self.last_bootloader_request = 0;
    }
};

test "bootloader capability and accepted control" {
    const std = @import("std");
    const identity = protocol.Identity{
        .board_id = "testbrd\x00".*,
        .profile_id = "default\x00".*,
        .digest = @splat(0),
        .dimensions = .{ .key_count = 1, .layer_count = 1 },
    };
    var transport = Transport.init(identity);
    transport.session = 42;
    const capabilities = try protocol.encodePacket(.{ .session = 42, .request = 1, .payload = .capabilities_request }, identity.dimensions, .host_to_device);
    transport.receive(&capabilities);
    transport.boundary();
    const reply = try protocol.decodePacket(&transport.controls[0], identity.dimensions, .device_to_host);
    try std.testing.expectEqual(protocol.capability_bootloader, reply.payload.capabilities);
    transport.control_count = 0;
    const boot = try protocol.encodePacket(.{ .session = 42, .request = 2, .payload = .enter_bootloader }, identity.dimensions, .host_to_device);
    transport.receive(&boot);
    transport.boundary();
    const boot_reply = try protocol.decodePacket(&transport.controls[0], identity.dimensions, .device_to_host);
    try std.testing.expectEqual(protocol.BootloaderResult.accepted, boot_reply.payload.bootloader_result);
    try std.testing.expectEqual(@as(u16, 2), boot_reply.request);
}

test "backpressure preserves snapshot head and overflow invalidates capture" {
    const std = @import("std");
    const identity = protocol.Identity{
        .board_id = "testbrd\x00".*,
        .profile_id = "default\x00".*,
        .digest = @splat(0),
        .dimensions = .{ .key_count = 1, .layer_count = 1 },
    };
    const Fake = struct {
        attempts: usize = 0,
        fn send(context: *anyopaque, _: *const protocol.Report) bool {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.attempts += 1;
            return false;
        }
    };
    var transport = Transport.init(identity);
    transport.session = 42;
    const request = try protocol.encodePacket(.{ .session = 42, .request = 1, .payload = .snapshot_request }, identity.dimensions, .host_to_device);
    transport.receive(&request);
    transport.boundary();
    var fake = Fake{};
    transport.pump(.{ .context = &fake, .send = Fake.send });
    try std.testing.expectEqual(@as(usize, 1), fake.attempts);
    try std.testing.expectEqual(@as(usize, 0), transport.control_head);
    try std.testing.expectEqual(@as(usize, 2), transport.control_count);
    const sink = transport.sink();
    for (0..delta_capacity + 1) |i| {
        _ = sink.write(sink.context, .{ .sequence = @intCast(i), .event = .{ .key = .{ .key_index = 0, .pressed = true, .layer = 0, .modifiers = .{} } } });
    }
    try std.testing.expectEqual(protocol.RecoveryReason.snapshot_invalidated, transport.recovery.?);
    try std.testing.expectEqual(@as(usize, 0), transport.control_count);
    try std.testing.expectEqual(@as(usize, 0), transport.delta_count);
    try std.testing.expectEqual(@as(u8, 1), transport.state.pressed[0]);
    try std.testing.expect(!transport.synchronized);
    transport.disconnect();
    try std.testing.expectEqual(@as(u8, 1), transport.state.pressed[0]);
    try std.testing.expectEqual(@as(u32, 0), transport.session);
}

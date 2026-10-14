// SPDX-License-Identifier: GPL-2.0
// Retained from conlorz/zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f,
// device-protocol/src/root.zig. See repository LICENSE for GPL version 2.
const std = @import("std");
const model = @import("core.zig");

pub const report_size = 32;
pub const Report = [report_size]u8;
pub const KeyEvent = struct { pressed: bool, key_index: model.KeyIndex, layer: model.LayerIndex, modifiers: model.Modifiers };
pub const LayerState = struct { active_layers: u16, highest_layer: model.LayerIndex, modifiers: model.Modifiers };
pub const Event = union(enum) { key: KeyEvent, layers: LayerState };
pub const Message = struct { sequence: u16, event: Event };
pub const ProtocolError = error{ InvalidDimensions, InvalidLength, InvalidMagic, UnsupportedVersion, UnsupportedKind, InvalidPayloadLength, InvalidReserved, InvalidPadding, InvalidBoolean, InvalidKeyIndex, InvalidLayer, InvalidLayerMask, InvalidSession, InvalidRequest, InvalidPart, InvalidIdentity, InvalidSignal, InvalidReason, InvalidAction, InvalidCallback, WrongDirection };

pub fn validate(message: Message, dimensions: model.KeymapDimensions) ProtocolError!void {
    if (dimensions.key_count == 0 or dimensions.layer_count == 0) return error.InvalidDimensions;
    switch (message.event) {
        .key => |key_value| {
            if (key_value.key_index >= dimensions.key_count) return error.InvalidKeyIndex;
            if (key_value.layer >= dimensions.layer_count) return error.InvalidLayer;
        },
        .layers => |layers| {
            if (layers.highest_layer >= dimensions.layer_count) return error.InvalidLayer;
            const allowed = (@as(u16, 1) << dimensions.layer_count) - 1;
            if (layers.active_layers & ~allowed != 0 or layers.active_layers & 1 == 0) return error.InvalidLayerMask;
            const highest: model.LayerIndex = @intCast(15 - @clz(layers.active_layers));
            if (highest != layers.highest_layer) return error.InvalidLayerMask;
        },
    }
}

pub fn encode(message: Message, dimensions: model.KeymapDimensions) ProtocolError!Report {
    try validate(message, dimensions);
    var report: Report = @splat(0);
    report[0] = 0xA7;
    report[1] = 1;
    report[3] = 4;
    std.mem.writeInt(u16, report[4..6], message.sequence, .little);
    switch (message.event) {
        .key => |key_value| {
            report[2] = 3;
            report[8] = @intFromBool(key_value.pressed);
            report[9] = key_value.key_index;
            report[10] = key_value.layer;
            report[11] = key_value.modifiers.toByte();
        },
        .layers => |layers| {
            report[2] = 1;
            std.mem.writeInt(u16, report[8..10], layers.active_layers, .little);
            report[10] = layers.highest_layer;
            report[11] = layers.modifiers.toByte();
        },
    }
    return report;
}

pub fn decode(bytes: []const u8, dimensions: model.KeymapDimensions) ProtocolError!Message {
    if (bytes.len != report_size) return error.InvalidLength;
    if (dimensions.key_count == 0 or dimensions.layer_count == 0) return error.InvalidDimensions;
    if (bytes[0] != 0xA7) return error.InvalidMagic;
    if (bytes[1] != 1) return error.UnsupportedVersion;
    if (bytes[2] != 1 and bytes[2] != 3) return error.UnsupportedKind;
    if (bytes[3] != 4) return error.InvalidPayloadLength;
    if (bytes[6] != 0 or bytes[7] != 0) return error.InvalidReserved;
    for (bytes[12..]) |byte| if (byte != 0) return error.InvalidPadding;
    if (bytes[10] >= dimensions.layer_count or bytes[10] > 15) return error.InvalidLayer;
    const event: Event = if (bytes[2] == 3) blk: {
        if (bytes[8] > 1) return error.InvalidBoolean;
        if (bytes[9] >= dimensions.key_count or bytes[9] > 127) return error.InvalidKeyIndex;
        break :blk .{ .key = .{ .pressed = bytes[8] == 1, .key_index = @intCast(bytes[9]), .layer = @intCast(bytes[10]), .modifiers = model.Modifiers.fromByte(bytes[11]) } };
    } else .{ .layers = .{ .active_layers = std.mem.readInt(u16, bytes[8..10], .little), .highest_layer = @intCast(bytes[10]), .modifiers = model.Modifiers.fromByte(bytes[11]) } };
    const message = Message{ .sequence = std.mem.readInt(u16, bytes[4..6], .little), .event = event };
    try validate(message, dimensions);
    return message;
}

pub const Direction = enum { host_to_device, device_to_host };
pub const SignalKind = enum(u8) { log_toggle = 1, overlay_toggle = 2, shutdown = 3 };
pub const Signal = struct { kind: SignalKind, pressed: bool };
pub const RecoveryReason = enum(u8) { overflow = 1, snapshot_invalidated = 2 };
pub const IdentityPart = struct { index: u8, bytes: [16]u8 = @splat(0) };
pub const SnapshotPart = struct { index: u8, bytes: [10]u8 };
pub const capability_bootloader: u16 = 1;
pub const BootloaderResult = enum(u8) { accepted = 1, unsupported = 2, duplicate = 3, busy = 4 };

test "bootloader extension keeps strict session correlation framing" {
    const dimensions = model.KeymapDimensions{ .key_count = 1, .layer_count = 1 };
    const request = Packet{ .session = 42, .request = 7, .payload = .enter_bootloader };
    const bytes = try encodePacket(request, dimensions, .host_to_device);
    try std.testing.expectEqualDeep(request, try decodePacket(&bytes, dimensions, .host_to_device));
    try std.testing.expectError(error.WrongDirection, decodePacket(&bytes, dimensions, .device_to_host));
    try std.testing.expectError(error.InvalidSession, encodePacket(.{ .session = 0, .request = 7, .payload = .enter_bootloader }, dimensions, .host_to_device));
    try std.testing.expectError(error.InvalidRequest, encodePacket(.{ .session = 42, .payload = .enter_bootloader }, dimensions, .host_to_device));
    var malformed = bytes;
    malformed[12] = 1;
    try std.testing.expectError(error.InvalidPadding, decodePacket(&malformed, dimensions, .host_to_device));
    const result = Packet{ .session = 42, .request = 7, .payload = .{ .bootloader_result = .accepted } };
    const reply = try encodePacket(result, dimensions, .device_to_host);
    try std.testing.expectEqualDeep(result, try decodePacket(&reply, dimensions, .device_to_host));
    const capabilities = Packet{ .session = 42, .request = 8, .payload = .{ .capabilities = capability_bootloader } };
    const capability_bytes = try encodePacket(capabilities, dimensions, .device_to_host);
    try std.testing.expectEqualDeep(capabilities, try decodePacket(&capability_bytes, dimensions, .device_to_host));
}
pub const Payload = union(enum(u8)) {
    hello = 10,
    identity: IdentityPart = 11,
    snapshot_request = 12,
    snapshot: SnapshotPart = 13,
    key: KeyEvent = 14,
    layers: LayerState = 15,
    recovery: RecoveryReason = 16,
    signal: Signal = 17,
    capabilities_request = 18,
    capabilities: u16 = 19,
    enter_bootloader = 20,
    bootloader_result: BootloaderResult = 21,
};
pub const Packet = struct {
    session: u32,
    sequence: u16 = 0,
    request: u16 = 0,
    // Hello nonce is the desired session token, stored separately from its zero header.
    nonce: u32 = 0,
    payload: Payload,
};
pub const Identity = struct {
    board_id: [8]u8,
    profile_id: [8]u8,
    digest: [16]u8,
    dimensions: model.KeymapDimensions,
};
pub const Snapshot = struct {
    pressed: [16]u8 = @splat(0),
    active_layers: u16 = 1,
    highest_layer: model.LayerIndex = 0,
    modifiers: model.Modifiers = .{},
};
pub const identity_body_size = 38;
pub const snapshot_body_size = 20;

pub fn validateId(id: [8]u8) ProtocolError!void {
    if (id[0] == 0) return error.InvalidIdentity;
    var ended = false;
    for (id) |byte| {
        if (byte == 0) {
            ended = true;
            continue;
        }
        if (ended or !(byte >= 'a' and byte <= 'z' or byte >= '0' and byte <= '9' or byte == '_')) return error.InvalidIdentity;
    }
}
pub fn validateIdentity(identity: Identity) ProtocolError!void {
    try validateId(identity.board_id);
    try validateId(identity.profile_id);
    try validate(.{ .sequence = 0, .event = .{ .layers = .{ .active_layers = 1, .highest_layer = 0, .modifiers = .{} } } }, identity.dimensions);
}
pub fn identityBody(identity: Identity, nonce: u32) ProtocolError![38]u8 {
    try validateIdentity(identity);
    if (nonce == 0) return error.InvalidSession;
    var body: [38]u8 = undefined;
    std.mem.writeInt(u32, body[0..4], nonce, .little);
    @memcpy(body[4..12], &identity.board_id);
    @memcpy(body[12..20], &identity.profile_id);
    @memcpy(body[20..36], &identity.digest);
    body[36] = identity.dimensions.key_count;
    body[37] = identity.dimensions.layer_count;
    return body;
}
pub fn decodeIdentityBody(body: [38]u8, nonce: u32) ProtocolError!Identity {
    if (nonce == 0 or std.mem.readInt(u32, body[0..4], .little) != nonce) return error.InvalidSession;
    if (body[36] == 0 or body[36] > 127 or body[37] == 0 or body[37] > 15) return error.InvalidDimensions;
    const identity = Identity{ .board_id = body[4..12].*, .profile_id = body[12..20].*, .digest = body[20..36].*, .dimensions = .{ .key_count = @intCast(body[36]), .layer_count = @intCast(body[37]) } };
    try validateIdentity(identity);
    return identity;
}
pub fn encodeSnapshotBody(snapshot: Snapshot, dimensions: model.KeymapDimensions) ProtocolError![20]u8 {
    try validate(.{ .sequence = 0, .event = .{ .layers = .{ .active_layers = snapshot.active_layers, .highest_layer = snapshot.highest_layer, .modifiers = snapshot.modifiers } } }, dimensions);
    for (@as(usize, dimensions.key_count)..128) |index| {
        if (snapshot.pressed[index / 8] & (@as(u8, 1) << @as(u3, @intCast(index % 8))) != 0) return error.InvalidKeyIndex;
    }
    var body: [20]u8 = undefined;
    @memcpy(body[0..16], &snapshot.pressed);
    std.mem.writeInt(u16, body[16..18], snapshot.active_layers, .little);
    body[18] = snapshot.highest_layer;
    body[19] = snapshot.modifiers.toByte();
    return body;
}
pub fn decodeSnapshotBody(body: [20]u8, dimensions: model.KeymapDimensions) ProtocolError!Snapshot {
    if (body[18] > 15) return error.InvalidLayer;
    const snapshot = Snapshot{ .pressed = body[0..16].*, .active_layers = std.mem.readInt(u16, body[16..18], .little), .highest_layer = @intCast(body[18]), .modifiers = model.Modifiers.fromByte(body[19]) };
    _ = try encodeSnapshotBody(snapshot, dimensions);
    return snapshot;
}
pub fn identityPackets(identity: Identity, nonce: u32, request: u16) ProtocolError![3]Packet {
    const body = try identityBody(identity, nonce);
    var packets: [3]Packet = undefined;
    for (&packets, 0..) |*packet, index| {
        var part = IdentityPart{ .index = @intCast(index) };
        const len: usize = if (index == 2) 6 else 16;
        @memcpy(part.bytes[0..len], body[index * 16 ..][0..len]);
        packet.* = .{ .session = nonce, .request = request, .payload = .{ .identity = part } };
    }
    return packets;
}
pub fn snapshotPackets(snapshot: Snapshot, dimensions: model.KeymapDimensions, session: u32, request: u16, boundary: u16) ProtocolError![2]Packet {
    const body = try encodeSnapshotBody(snapshot, dimensions);
    return .{
        .{ .session = session, .request = request, .sequence = boundary, .payload = .{ .snapshot = .{ .index = 0, .bytes = body[0..10].* } } },
        .{ .session = session, .request = request, .sequence = boundary, .payload = .{ .snapshot = .{ .index = 1, .bytes = body[10..20].* } } },
    };
}
fn payloadLength(payload: Payload) ProtocolError!u8 {
    return switch (payload) {
        .hello => 4,
        .snapshot_request, .capabilities_request, .enter_bootloader => 0,
        .capabilities => 2,
        .bootloader_result => 1,
        .key, .layers => 4,
        .recovery => 1,
        .signal => 2,
        .identity => |part| if (part.index < 2) 18 else if (part.index == 2) 8 else error.InvalidPart,
        .snapshot => |part| if (part.index < 2) 12 else error.InvalidPart,
    };
}
pub fn validatePacket(packet: Packet, dimensions: model.KeymapDimensions, direction: Direction) ProtocolError!void {
    if (dimensions.key_count == 0 or dimensions.layer_count == 0) return error.InvalidDimensions;
    const host = switch (packet.payload) {
        .hello, .snapshot_request, .capabilities_request, .enter_bootloader => true,
        else => false,
    };
    if (host != (direction == .host_to_device)) return error.WrongDirection;
    if (packet.payload == .hello) {
        if (packet.session != 0 or packet.nonce == 0) return error.InvalidSession;
    } else if (packet.session == 0 or packet.nonce != 0) return error.InvalidSession;
    const transaction = switch (packet.payload) {
        .hello, .identity, .snapshot_request, .snapshot, .capabilities_request, .capabilities, .enter_bootloader, .bootloader_result => true,
        else => false,
    };
    if ((packet.request != 0) != transaction) return error.InvalidRequest;
    if (packet.payload != .snapshot and packet.payload != .key and packet.payload != .layers and packet.payload != .signal and packet.sequence != 0) return error.InvalidReserved;
    _ = try payloadLength(packet.payload);
    switch (packet.payload) {
        .key => |key| try validate(.{ .sequence = packet.sequence, .event = .{ .key = key } }, dimensions),
        .layers => |layers| try validate(.{ .sequence = packet.sequence, .event = .{ .layers = layers } }, dimensions),
        .identity => |part| if (part.index == 2) {
            for (part.bytes[6..]) |byte| if (byte != 0) return error.InvalidPadding;
        },
        else => {},
    }
}
pub fn encodePacket(packet: Packet, dimensions: model.KeymapDimensions, direction: Direction) ProtocolError!Report {
    try validatePacket(packet, dimensions, direction);
    var bytes: Report = @splat(0);
    bytes[0] = 0xA7;
    bytes[1] = 2;
    bytes[2] = @backingInt(packet.payload);
    bytes[3] = try payloadLength(packet.payload);
    std.mem.writeInt(u32, bytes[4..8], packet.session, .little);
    std.mem.writeInt(u16, bytes[8..10], packet.sequence, .little);
    std.mem.writeInt(u16, bytes[10..12], packet.request, .little);
    switch (packet.payload) {
        .hello => std.mem.writeInt(u32, bytes[12..16], packet.nonce, .little),
        .identity => |part| {
            bytes[12] = part.index;
            bytes[13] = 3;
            @memcpy(bytes[14..][0 .. bytes[3] - 2], part.bytes[0 .. bytes[3] - 2]);
        },
        .snapshot => |part| {
            bytes[12] = part.index;
            bytes[13] = 2;
            @memcpy(bytes[14..24], &part.bytes);
        },
        .key => |key_value| {
            bytes[12] = @intFromBool(key_value.pressed);
            bytes[13] = key_value.key_index;
            bytes[14] = key_value.layer;
            bytes[15] = key_value.modifiers.toByte();
        },
        .layers => |layers| {
            std.mem.writeInt(u16, bytes[12..14], layers.active_layers, .little);
            bytes[14] = layers.highest_layer;
            bytes[15] = layers.modifiers.toByte();
        },
        .recovery => |reason| bytes[12] = @backingInt(reason),
        .signal => |signal| {
            bytes[12] = @backingInt(signal.kind);
            bytes[13] = @intFromBool(signal.pressed);
        },
        .snapshot_request, .capabilities_request, .enter_bootloader => {},
        .capabilities => |value| std.mem.writeInt(u16, bytes[12..14], value, .little),
        .bootloader_result => |value| bytes[12] = @backingInt(value),
    }
    return bytes;
}
pub fn decodePacket(bytes: []const u8, dimensions: model.KeymapDimensions, direction: Direction) ProtocolError!Packet {
    if (bytes.len != 32) return error.InvalidLength;
    if (bytes[0] != 0xA7) return error.InvalidMagic;
    if (bytes[1] != 2) return error.UnsupportedVersion;
    var packet = Packet{ .session = std.mem.readInt(u32, bytes[4..8], .little), .sequence = std.mem.readInt(u16, bytes[8..10], .little), .request = std.mem.readInt(u16, bytes[10..12], .little), .payload = .snapshot_request };
    packet.payload = switch (bytes[2]) {
        10 => blk: {
            packet.nonce = std.mem.readInt(u32, bytes[12..16], .little);
            break :blk .hello;
        },
        11 => blk: {
            if (bytes[12] > 2 or bytes[13] != 3) return error.InvalidPart;
            var part = IdentityPart{ .index = bytes[12] };
            const len: usize = if (part.index == 2) 6 else 16;
            @memcpy(part.bytes[0..len], bytes[14..][0..len]);
            break :blk .{ .identity = part };
        },
        12 => .snapshot_request,
        13 => blk: {
            if (bytes[12] > 1 or bytes[13] != 2) return error.InvalidPart;
            break :blk .{ .snapshot = .{ .index = bytes[12], .bytes = bytes[14..24].* } };
        },
        14 => blk: {
            if (bytes[12] > 1) return error.InvalidBoolean;
            if (bytes[13] > 127) return error.InvalidKeyIndex;
            if (bytes[14] > 15) return error.InvalidLayer;
            break :blk .{ .key = .{ .pressed = bytes[12] != 0, .key_index = @intCast(bytes[13]), .layer = @intCast(bytes[14]), .modifiers = model.Modifiers.fromByte(bytes[15]) } };
        },
        15 => blk: {
            if (bytes[14] > 15) return error.InvalidLayer;
            break :blk .{ .layers = .{ .active_layers = std.mem.readInt(u16, bytes[12..14], .little), .highest_layer = @intCast(bytes[14]), .modifiers = model.Modifiers.fromByte(bytes[15]) } };
        },
        16 => .{ .recovery = std.enums.fromInt(RecoveryReason, bytes[12]) orelse return error.InvalidReason },
        17 => blk: {
            if (bytes[13] > 1) return error.InvalidBoolean;
            break :blk .{ .signal = .{ .kind = std.enums.fromInt(SignalKind, bytes[12]) orelse return error.InvalidSignal, .pressed = bytes[13] != 0 } };
        },
        18 => .capabilities_request,
        19 => .{ .capabilities = std.mem.readInt(u16, bytes[12..14], .little) },
        20 => .enter_bootloader,
        21 => .{ .bootloader_result = std.enums.fromInt(BootloaderResult, bytes[12]) orelse return error.InvalidReason },
        else => return error.UnsupportedKind,
    };
    const len = try payloadLength(packet.payload);
    if (bytes[3] != len) return error.InvalidPayloadLength;
    for (bytes[12 + len ..]) |byte| if (byte != 0) return error.InvalidPadding;
    try validatePacket(packet, dimensions, direction);
    return packet;
}

pub const CallbackIdentity = struct { id: u8, behavior: []const u8 };
pub const IdentityInput = struct {
    board_id: [8]u8,
    profile_id: [8]u8,
    dimensions: model.KeymapDimensions,
    keys: []const ?model.KeyDef,
    sides: []const model.Side,
    combos: []const model.Combo2Def,
    encoders: []const model.EncoderAction,
    callbacks: []const CallbackIdentity,
};
const Canonical = struct {
    hash: std.crypto.hash.sha2.Sha256 = .init(.{}),
    dimensions: model.KeymapDimensions,
    callbacks: []const CallbackIdentity,
    fn byte(self: *Canonical, value: u8) void {
        self.hash.update(&.{value});
    }
    fn boolean(self: *Canonical, value: bool) void {
        self.byte(@intFromBool(value));
    }
    fn word(self: *Canonical, value: u16) void {
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, value, .little);
        self.hash.update(&bytes);
    }
    fn count(self: *Canonical, value: usize) ProtocolError!void {
        if (value > 65535) return error.InvalidIdentity;
        self.word(@intCast(value));
    }
    fn custom(self: *Canonical, value: ?u8) ProtocolError!void {
        self.boolean(value != null);
        if (value) |id| {
            if (id == 0) return error.InvalidCallback;
            if (id < 253) {
                var declared = false;
                for (self.callbacks) |callback| {
                    if (callback.id == id) declared = true;
                }
                if (!declared) return error.InvalidCallback;
            }
            self.byte(id);
        }
    }
    fn hold(self: *Canonical, value: model.HoldDef) ProtocolError!void {
        self.byte(value.hold_modifiers.toByte());
        self.boolean(value.hold_layer != null);
        if (value.hold_layer) |layer| {
            if (layer >= self.dimensions.layer_count) return error.InvalidLayer;
            self.byte(layer);
        }
        try self.custom(value.custom);
    }
    fn tap(self: *Canonical, value: model.TapDef) ProtocolError!void {
        self.boolean(value.key_press != null);
        if (value.key_press) |key_value| {
            self.byte(key_value.tap_keycode);
            self.byte(key_value.tap_modifiers.toByte());
            self.boolean(key_value.dead);
        }
        self.boolean(value.one_shot != null);
        if (value.one_shot) |hold_value| try self.hold(hold_value);
        try self.custom(value.custom);
        self.boolean(value.media_key != null);
        if (value.media_key) |media| self.word(@backingInt(media));
        self.boolean(value.mouse_action != null);
        if (value.mouse_action) |mouse| self.byte(switch (mouse) {
            .LeftButton => 0,
            .RightButton => 1,
            .MiddleButton => 2,
            .Button4 => 3,
            .Button5 => 4,
            .WheelUp => 5,
            .WheelDown => 6,
            .WheelLeft => 7,
            .WheelRight => 8,
        });
    }
    fn key(self: *Canonical, value: ?model.KeyDef) ProtocolError!void {
        const action = value orelse {
            self.byte(5);
            return;
        };
        switch (action) {
            .none => self.byte(0),
            .tap_only => |tap_value| {
                self.byte(1);
                try self.tap(tap_value);
            },
            .hold_only => |hold_value| {
                self.byte(2);
                try self.hold(hold_value);
            },
            .tap_hold => |value_th| {
                self.byte(3);
                try self.tap(value_th.tap);
                try self.hold(value_th.hold);
                self.word(value_th.tapping_term.ms);
                self.boolean(value_th.retro_tapping);
            },
            .tap_with_autofire => |fire| {
                self.byte(4);
                try self.tap(fire.tap);
                self.word(fire.initial_delay.ms);
                self.word(fire.repeat_interval.ms);
            },
        }
    }
};

/// Hashes semantic fields, never pointer addresses or compiler object representations.
pub fn computeIdentity(input: IdentityInput) ProtocolError!Identity {
    var identity = Identity{ .board_id = input.board_id, .profile_id = input.profile_id, .digest = undefined, .dimensions = input.dimensions };
    try validateIdentity(identity);
    if (input.keys.len != @as(usize, input.dimensions.key_count) * input.dimensions.layer_count or input.sides.len != input.dimensions.key_count) return error.InvalidDimensions;
    if (input.callbacks.len > 252) return error.InvalidCallback;
    for (input.callbacks, 0..) |callback, index| {
        if (callback.id == 0 or callback.id >= 253 or callback.behavior.len == 0 or callback.behavior.len > 65535) return error.InvalidCallback;
        for (callback.behavior) |byte| if (byte < 0x21 or byte > 0x7E) return error.InvalidCallback;
        for (input.callbacks[0..index]) |earlier| if (earlier.id == callback.id) return error.InvalidCallback;
    }
    var canonical = Canonical{ .dimensions = input.dimensions, .callbacks = input.callbacks };
    canonical.hash.update("zigmkay-profile-v1\x00");
    canonical.hash.update(&input.board_id);
    canonical.hash.update(&input.profile_id);
    canonical.byte(input.dimensions.key_count);
    canonical.byte(input.dimensions.layer_count);
    try canonical.count(input.keys.len);
    for (input.keys) |key_value| try canonical.key(key_value);
    try canonical.count(input.sides.len);
    for (input.sides) |side| canonical.byte(switch (side) {
        .L => 0,
        .R => 1,
        .X => 2,
    });
    try canonical.count(input.combos.len);
    for (input.combos) |combo| {
        if (combo.key_indexes[0] >= input.dimensions.key_count or combo.key_indexes[1] >= input.dimensions.key_count or combo.key_indexes[0] == combo.key_indexes[1]) return error.InvalidKeyIndex;
        if (combo.layer >= input.dimensions.layer_count) return error.InvalidLayer;
        canonical.byte(combo.key_indexes[0]);
        canonical.byte(combo.key_indexes[1]);
        canonical.word(combo.timeout.ms);
        canonical.byte(combo.layer);
        try canonical.key(combo.key_def);
    }
    try canonical.count(input.encoders.len);
    for (input.encoders) |encoder| try canonical.tap(encoder.tap);
    try canonical.count(input.callbacks.len);
    for (input.callbacks) |callback| {
        canonical.byte(callback.id);
        try canonical.count(callback.behavior.len);
        canonical.hash.update(callback.behavior);
    }
    var full: [32]u8 = undefined;
    canonical.hash.final(&full);
    identity.digest = full[0..16].*;
    return identity;
}

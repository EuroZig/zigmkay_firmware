// SPDX-License-Identifier: GPL-2.0
// Literal fixtures retained from conlorz/zigmkay_firmware
// 3ee4135d308f18f15cc51b1d73e33e1b36bf517f, tests/test_protocol_session.zig.
const std = @import("std");

// Independent literals: they precede codec implementation and define the wire.
pub const hello: [32]u8 = .{ 0xA7, 2, 10, 4, 0, 0, 0, 0, 0, 0, 1, 0, 0x44, 0x33, 0x22, 0x11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
// Board "lk7", profile "danish", digest bytes 00..0f, dimensions 34/4.
pub const identity_parts: [3][32]u8 = .{
    .{ 0xA7, 2, 11, 18, 0x44, 0x33, 0x22, 0x11, 0, 0, 1, 0, 0, 3, 0x44, 0x33, 0x22, 0x11, 'l', 'k', '7', 0, 0, 0, 0, 0, 'd', 'a', 'n', 'i', 0, 0 },
    .{ 0xA7, 2, 11, 18, 0x44, 0x33, 0x22, 0x11, 0, 0, 1, 0, 1, 3, 's', 'h', 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0, 0 },
    .{ 0xA7, 2, 11, 8, 0x44, 0x33, 0x22, 0x11, 0, 0, 1, 0, 2, 3, 12, 13, 14, 15, 34, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};
pub const snapshot_request: [32]u8 = .{ 0xA7, 2, 12, 0, 0x44, 0x33, 0x22, 0x11, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
// Keys 0 and 30 held, arrows active, persistent left control. Next delta=65535.
pub const snapshot_parts: [2][32]u8 = .{
    .{ 0xA7, 2, 13, 12, 0x44, 0x33, 0x22, 0x11, 0xFF, 0xFF, 2, 0, 0, 2, 1, 0, 0, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 0xA7, 2, 13, 12, 0x44, 0x33, 0x22, 0x11, 0xFF, 0xFF, 2, 0, 1, 2, 0, 0, 0, 0, 0, 0, 3, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
};
pub const release: [32]u8 = .{ 0xA7, 2, 14, 4, 0x44, 0x33, 0x22, 0x11, 0xFF, 0xFF, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
pub const overflow: [32]u8 = .{ 0xA7, 2, 16, 1, 0x44, 0x33, 0x22, 0x11, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

test "v2 independent fixtures define complete report boundaries and zero padding" {
    const reports = .{hello} ++ identity_parts ++ .{snapshot_request} ++ snapshot_parts ++ .{ release, overflow };
    for (reports) |report| {
        try std.testing.expectEqual(@as(u8, 0xA7), report[0]);
        try std.testing.expectEqual(@as(u8, 2), report[1]);
        try std.testing.expect(report[3] <= 20);
        for (report[12 + report[3] ..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

const zigmkay = @import("zigmkay");
const protocol = zigmkay.device_protocol;
const model = zigmkay.core;
const dimensions = model.KeymapDimensions{ .key_count = 34, .layer_count = 4 };
const fixture_identity = protocol.Identity{ .board_id = .{ 'l', 'k', '7', 0, 0, 0, 0, 0 }, .profile_id = .{ 'd', 'a', 'n', 'i', 's', 'h', 0, 0 }, .digest = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }, .dimensions = dimensions };

test "v2 codec matches independent identity snapshot recovery and control literals" {
    const hello_packet = protocol.Packet{ .session = 0, .request = 1, .nonce = 0x11223344, .payload = .hello };
    try std.testing.expectEqual(hello, try protocol.encodePacket(hello_packet, dimensions, .host_to_device));
    const identities = try protocol.identityPackets(fixture_identity, 0x11223344, 1);
    for (identities, identity_parts) |packet, literal| {
        try std.testing.expectEqual(literal, try protocol.encodePacket(packet, dimensions, .device_to_host));
        try std.testing.expectEqualDeep(packet, try protocol.decodePacket(&literal, dimensions, .device_to_host));
    }
    var snapshot = protocol.Snapshot{ .active_layers = 3, .highest_layer = 1, .modifiers = .{ .left_ctrl = true } };
    snapshot.pressed[0] = 1;
    snapshot.pressed[3] = 0x40;
    const snapshots = try protocol.snapshotPackets(snapshot, dimensions, 0x11223344, 2, 65535);
    for (snapshots, snapshot_parts) |packet, literal| {
        try std.testing.expectEqual(literal, try protocol.encodePacket(packet, dimensions, .device_to_host));
        try std.testing.expectEqualDeep(packet, try protocol.decodePacket(&literal, dimensions, .device_to_host));
    }
    try std.testing.expectEqualDeep(snapshot, try protocol.decodeSnapshotBody(try protocol.encodeSnapshotBody(snapshot, dimensions), dimensions));
    for ([_]protocol.Report{ snapshot_request, release, overflow }) |literal| {
        const direction: protocol.Direction = if (literal[2] == 12) .host_to_device else .device_to_host;
        try std.testing.expectEqual(literal, try protocol.encodePacket(try protocol.decodePacket(&literal, dimensions, direction), dimensions, direction));
    }
    try std.testing.expectEqualDeep(fixture_identity, try protocol.decodeIdentityBody(try protocol.identityBody(fixture_identity, 0x11223344), 0x11223344));
}

test "v2 invalid framing dimensions transaction fields and fragments reject" {
    try std.testing.expectError(error.InvalidDimensions, protocol.decodePacket(&hello, .{ .key_count = 0, .layer_count = 4 }, .host_to_device));
    try std.testing.expectError(error.WrongDirection, protocol.decodePacket(&hello, dimensions, .device_to_host));
    try std.testing.expectError(error.InvalidLength, protocol.decodePacket(hello[0..31], dimensions, .host_to_device));
    const cases = .{ .{ 0, 0, error.InvalidMagic }, .{ 1, 1, error.UnsupportedVersion }, .{ 2, 0, error.UnsupportedKind }, .{ 3, 3, error.InvalidPayloadLength }, .{ 4, 1, error.InvalidSession }, .{ 8, 1, error.InvalidReserved }, .{ 10, 0, error.InvalidRequest }, .{ 31, 1, error.InvalidPadding } };
    inline for (cases) |case| {
        var bad = hello;
        bad[case[0]] = case[1];
        try std.testing.expectError(case[2], protocol.decodePacket(&bad, dimensions, .host_to_device));
    }
    for ([_]u8{ 0, 4, 255 }) |count| {
        var bad = identity_parts[0];
        bad[13] = count;
        try std.testing.expectError(error.InvalidPart, protocol.decodePacket(&bad, dimensions, .device_to_host));
    }
    var bad = snapshot_parts[0];
    bad[12] = 2;
    try std.testing.expectError(error.InvalidPart, protocol.decodePacket(&bad, dimensions, .device_to_host));
    var body = try protocol.encodeSnapshotBody(.{}, dimensions);
    body[15] = 0x80;
    try std.testing.expectError(error.InvalidKeyIndex, protocol.decodeSnapshotBody(body, dimensions));
    body = try protocol.encodeSnapshotBody(.{}, dimensions);
    body[16] = 0;
    try std.testing.expectError(error.InvalidLayerMask, protocol.decodeSnapshotBody(body, dimensions));
    var identity_body = try protocol.identityBody(fixture_identity, 0x11223344);
    identity_body[5] = 0;
    identity_body[6] = 'a';
    try std.testing.expectError(error.InvalidIdentity, protocol.decodeIdentityBody(identity_body, 0x11223344));
    identity_body = try protocol.identityBody(fixture_identity, 0x11223344);
    identity_body[36] = 128;
    try std.testing.expectError(error.InvalidDimensions, protocol.decodeIdentityBody(identity_body, 0x11223344));
}

test "v2 arbitrary mutations either fail or reencode exactly" {
    for ([_]protocol.Report{ hello, identity_parts[0], identity_parts[2], snapshot_parts[0], release, overflow }) |seed| {
        const direction: protocol.Direction = if (seed[2] == 10) .host_to_device else .device_to_host;
        for (0..32) |index| for (0..256) |value| {
            var report = seed;
            report[index] = @intCast(value);
            const decoded = protocol.decodePacket(&report, dimensions, direction) catch continue;
            try std.testing.expectEqual(report, try protocol.encodePacket(decoded, dimensions, direction));
        };
    }
}

test "v2 layer and signal literals preserve modifier bits and shared sequence" {
    const layers: protocol.Report = [_]u8{ 0xA7, 2, 15, 4, 0x44, 0x33, 0x22, 0x11, 0x34, 0x12, 0, 0, 3, 0, 1, 0x81 } ++ @as([16]u8, @splat(0));
    const signal: protocol.Report = [_]u8{ 0xA7, 2, 17, 2, 0x44, 0x33, 0x22, 0x11, 0x35, 0x12, 0, 0, 2, 1 } ++ @as([18]u8, @splat(0));
    try std.testing.expectEqual(layers, try protocol.encodePacket(.{ .session = 0x11223344, .sequence = 0x1234, .payload = .{ .layers = .{ .active_layers = 3, .highest_layer = 1, .modifiers = model.Modifiers.fromByte(0x81) } } }, dimensions, .device_to_host));
    try std.testing.expectEqual(signal, try protocol.encodePacket(.{ .session = 0x11223344, .sequence = 0x1235, .payload = .{ .signal = .{ .kind = .overlay_toggle, .pressed = true } } }, dimensions, .device_to_host));
    for ([_]protocol.Report{ layers, signal }) |literal| {
        try std.testing.expectEqual(literal, try protocol.encodePacket(try protocol.decodePacket(&literal, dimensions, .device_to_host), dimensions, .device_to_host));
    }
}
fn key(sequence: u16, pressed: bool, index: model.KeyIndex, layer: model.LayerIndex) protocol.Message {
    return .{ .sequence = sequence, .event = .{ .key = .{ .pressed = pressed, .key_index = index, .layer = layer, .modifiers = .{} } } };
}

fn golden(prefix: [12]u8) protocol.Report {
    return prefix ++ @as([20]u8, @splat(0));
}

test "golden wire bytes are independent of memory layout" {
    const expected = golden(.{ 0xA7, 1, 3, 4, 0x34, 0x12, 0, 0, 1, 30, 2, 0x81 });
    var message = key(0x1234, true, 30, 2);
    message.event.key.modifiers = model.Modifiers.fromByte(0x81);
    try std.testing.expectEqual(expected, try protocol.encode(message, dimensions));
    try std.testing.expectEqualDeep(message, try protocol.decode(&expected, dimensions));
    const layer_message = protocol.Message{ .sequence = 3, .event = .{ .layers = .{ .active_layers = 3, .highest_layer = 1, .modifiers = .{} } } };
    const layer_bytes = golden(.{ 0xA7, 1, 1, 4, 3, 0, 0, 0, 3, 0, 1, 0 });
    try std.testing.expectEqual(layer_bytes, try protocol.encode(layer_message, dimensions));
    try std.testing.expectEqualDeep(layer_message, try protocol.decode(&layer_bytes, dimensions));
}

test "decoder rejects malformed framing and values before narrowing" {
    const valid = golden(.{ 0xA7, 1, 3, 4, 0, 0, 0, 0, 1, 0, 0, 0 });
    try std.testing.expectError(error.InvalidDimensions, protocol.decode(&valid, .{ .key_count = 0, .layer_count = 4 }));
    var long: [33]u8 = @splat(0);
    @memcpy(long[0..32], &valid);
    for (0..34) |len| {
        if (len != 32) try std.testing.expectError(error.InvalidLength, protocol.decode(long[0..len], dimensions));
    }
    const cases = .{
        .{ 0, 0, error.InvalidMagic },
        .{ 1, 2, error.UnsupportedVersion },
        .{ 2, 9, error.UnsupportedKind },
        .{ 3, 3, error.InvalidPayloadLength },
        .{ 6, 1, error.InvalidReserved },
        .{ 7, 1, error.InvalidReserved },
        .{ 8, 2, error.InvalidBoolean },
        .{ 9, 34, error.InvalidKeyIndex },
        .{ 9, 255, error.InvalidKeyIndex },
        .{ 10, 4, error.InvalidLayer },
        .{ 10, 255, error.InvalidLayer },
        .{ 31, 1, error.InvalidPadding },
    };
    inline for (cases) |case| {
        var bytes = valid;
        bytes[case[0]] = case[1];
        try std.testing.expectError(case[2], protocol.decode(&bytes, dimensions));
    }
}

test "active mask requires the base layer and correct highest layer" {
    var message = protocol.Message{ .sequence = 0, .event = .{ .layers = .{ .active_layers = 0, .highest_layer = 0, .modifiers = .{} } } };
    try std.testing.expectError(error.InvalidLayerMask, protocol.encode(message, dimensions));
    message.event.layers.active_layers = 0x11;
    try std.testing.expectError(error.InvalidLayerMask, protocol.encode(message, dimensions));
    message.event.layers.active_layers = 3;
    try std.testing.expectError(error.InvalidLayerMask, protocol.encode(message, dimensions));
    message.event.layers.highest_layer = 1;
    _ = try protocol.encode(message, dimensions);
    try std.testing.expectError(error.InvalidDimensions, protocol.encode(key(0, true, 0, 0), .{ .key_count = 0, .layer_count = 4 }));
    try std.testing.expectError(error.InvalidLayer, protocol.encode(key(0, true, 0, 4), dimensions));
    try std.testing.expectError(error.InvalidKeyIndex, protocol.encode(key(0, true, 34, 0), dimensions));
}
test "arbitrary reports either validate or fail without panicking" {
    const seed = golden(.{ 0xA7, 1, 3, 4, 0, 0, 0, 0, 1, 0, 0, 0 });
    for (0..32) |index| {
        for (0..256) |value| {
            var bytes = seed;
            bytes[index] = @intCast(value);
            const result = protocol.decode(&bytes, dimensions) catch continue;
            try protocol.validate(result, dimensions);
        }
    }
    var random = std.Random.DefaultPrng.init(0xA701);
    for (0..1000) |_| {
        var bytes: protocol.Report = undefined;
        random.random().bytes(&bytes);
        const result = protocol.decode(&bytes, dimensions) catch continue;
        try protocol.validate(result, dimensions);
    }
}

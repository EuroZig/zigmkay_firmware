const core = @import("zigmkay").core;

/// A supplied/exported module owns its canonical identity. Never infer one
/// from captions, local paths or a default profile with unknown provenance.
pub fn companionIdentity(comptime keymap: type, comptime enabled: bool) ?@import("zigmkay").device_protocol.Identity {
    if (!enabled) return null;
    @setEvalBranchQuota(500000);
    const protocol = @import("zigmkay").device_protocol;
    if (!@hasDecl(keymap, "identity")) @compileError("Companion telemetry requires a supplied canonical keymap identity");
    const identity = keymap.identity(protocol);
    protocol.validateIdentity(identity) catch @compileError("Invalid supplied companion identity");
    return identity;
}

/// Wiring fixes the key count and side ownership; a supplied module owns layers.
pub fn validate(comptime keymap: type, comptime key_count: usize, comptime sides: ?[]const core.Side) core.KeymapDimensions {
    if (keymap.keymap.len == 0) @compileError("Keymap must contain at least one layer");
    for (keymap.keymap) |layer| {
        if (layer.len != key_count) @compileError("Keymap key count does not match board wiring");
    }
    if (@hasDecl(keymap, "key_count") and keymap.key_count != key_count)
        @compileError("Declared key count does not match board wiring");
    if (@hasDecl(keymap, "dimensions")) {
        if (keymap.dimensions.key_count != key_count or keymap.dimensions.layer_count != keymap.keymap.len)
            @compileError("Declared dimensions do not match supplied keymap");
    }
    if (sides) |board_sides| {
        if (board_sides.len != key_count) @compileError("Board sides do not match board wiring");
        if (@hasDecl(keymap, "sides")) {
            if (keymap.sides.len != key_count) @compileError("Keymap sides do not match board wiring");
            for (keymap.sides, board_sides) |actual, expected| {
                if (actual != expected) @compileError("Keymap sides differ from board side ownership");
            }
        }
    }
    return .{ .key_count = key_count, .layer_count = keymap.keymap.len };
}

/// Board encoder indices remain fixed even when the action behavior is supplied.
pub fn encoderActions(comptime keymap: type, comptime defaults: anytype) @TypeOf(defaults) {
    if (@hasDecl(keymap, "encoder_actions")) {
        if (keymap.encoder_actions.len != defaults.len)
            @compileError("Encoder action slot count does not match board wiring");
        return keymap.encoder_actions;
    }
    return defaults;
}

test "supplied layers preserve board dimensions and sides" {
    const std = @import("std");
    const fixture = struct {
        pub const keymap = [3][2]?core.KeyDef{ .{ null, null }, .{ null, null }, .{ null, null } };
        pub const sides = [2]core.Side{ .L, .R };
    };
    const dimensions = comptime validate(fixture, 2, &.{ .L, .R });
    try std.testing.expectEqual(@as(usize, 2), dimensions.key_count);
    try std.testing.expectEqual(@as(usize, 3), dimensions.layer_count);
}

test "encoder behavior override preserves fixed slots and fallback" {
    const std = @import("std");
    const defaults = [2]core.EncoderAction{
        .{ .tap = .{ .media_key = .VolumeUp } },
        .{ .tap = .{ .media_key = .VolumeDown } },
    };
    const fixture = struct {
        pub const encoder_actions = [2]core.EncoderAction{
            .{ .tap = .{ .media_key = .VolumeDown } },
            .{ .tap = .{ .media_key = .VolumeUp } },
        };
    };
    const overridden = comptime encoderActions(fixture, defaults);
    const fallback = comptime encoderActions(struct {}, defaults);
    try std.testing.expectEqual(core.MediaCode.VolumeDown, overridden[0].tap.media_key);
    try std.testing.expectEqual(core.MediaCode.VolumeUp, fallback[0].tap.media_key);
}

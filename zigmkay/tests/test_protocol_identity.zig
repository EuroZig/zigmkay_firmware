// SPDX-License-Identifier: GPL-2.0
// Retained from conlorz/zigmkay_firmware
// 3ee4135d308f18f15cc51b1d73e33e1b36bf517f, tests/test_protocol_session.zig.
const std = @import("std");
const zigmkay = @import("zigmkay");
const protocol = zigmkay.device_protocol;
const model = zigmkay.core;
const base_keys = [_]?model.KeyDef{.{ .tap_only = .{ .key_press = .{ .tap_keycode = 4 } } }};
const base_input = protocol.IdentityInput{ .board_id = .{ 't', 'e', 's', 't', 0, 0, 0, 0 }, .profile_id = .{ 'b', 'a', 's', 'e', 0, 0, 0, 0 }, .dimensions = .{ .key_count = 1, .layer_count = 1 }, .keys = &base_keys, .sides = &.{.L}, .combos = &.{}, .encoders = &.{}, .callbacks = &.{} };

test "canonical profile digest uses independent semantic bytes" {
    const literal = "zigmkay-profile-v1\x00" ++ "test\x00\x00\x00\x00" ++ "base\x00\x00\x00\x00" ++ [_]u8{ 1, 1, 1, 0, 1, 1, 4, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 };
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(literal, &digest, .{});
    const identity = try protocol.computeIdentity(base_input);
    try std.testing.expectEqualSlices(u8, digest[0..16], &identity.digest);
    try std.testing.expectEqual([_]u8{ 0x11, 0xb5, 0x59, 0x62, 0xb8, 0x78, 0x55, 0xf9, 0x41, 0xde, 0x48, 0x43, 0x92, 0xa9, 0x66, 0x50 }, identity.digest);
}

test "identity changes cover optional actions sides combos encoders and callback declarations" {
    const original = (try protocol.computeIdentity(base_input)).digest;
    const variants = [_]?model.KeyDef{ null, .none, .{ .tap_only = .{ .key_press = .{ .tap_keycode = 4, .dead = true } } }, .{ .tap_only = .{ .key_press = .{ .tap_keycode = 4, .tap_modifiers = .{ .left_shift = true } } } }, .{ .tap_only = .{ .one_shot = .{ .hold_modifiers = .{ .left_ctrl = true } } } }, .{ .tap_only = .{ .media_key = .VolumeUp } }, .{ .tap_only = .{ .mouse_action = .WheelLeft } }, .{ .hold_only = .{ .hold_layer = 0 } }, .{ .tap_hold = .{ .tap = .{}, .hold = .{}, .tapping_term = .{ .ms = 150 }, .retro_tapping = true } }, .{ .tap_with_autofire = .{ .tap = .{}, .initial_delay = .{ .ms = 10 }, .repeat_interval = .{ .ms = 20 } } } };
    for (variants) |variant| {
        var input = base_input;
        input.keys = &.{variant};
        try std.testing.expect(!std.mem.eql(u8, &original, &(try protocol.computeIdentity(input)).digest));
    }
    var input = base_input;
    input.sides = &.{.R};
    try std.testing.expect(!std.mem.eql(u8, &original, &(try protocol.computeIdentity(input)).digest));
    input = base_input;
    input.encoders = &.{.{ .tap = .{ .custom = 1 } }};
    input.callbacks = &.{.{ .id = 1, .behavior = "combined-tap-hold-v1" }};
    const callback_v1 = try protocol.computeIdentity(input);
    input.callbacks = &.{.{ .id = 1, .behavior = "combined-tap-hold-v2" }};
    try std.testing.expect(!std.mem.eql(u8, &callback_v1.digest, &(try protocol.computeIdentity(input)).digest));
    input.callbacks = &.{};
    try std.testing.expectError(error.InvalidCallback, protocol.computeIdentity(input));
    input = base_input;
    input.keys = &.{.{ .hold_only = .{ .hold_layer = 1 } }};
    try std.testing.expectError(error.InvalidLayer, protocol.computeIdentity(input));
    input = base_input;
    input.callbacks = &.{ .{ .id = 1, .behavior = "a" }, .{ .id = 1, .behavior = "b" } };
    try std.testing.expectError(error.InvalidCallback, protocol.computeIdentity(input));
    input = base_input;
    input.dimensions.key_count = 2;
    input.keys = &.{ base_keys[0], base_keys[0] };
    input.sides = &.{ .L, .L };
    const no_combo = try protocol.computeIdentity(input);
    input.combos = &.{.{ .key_indexes = .{ 0, 1 }, .timeout = .{ .ms = 40 }, .layer = 0, .key_def = .none }};
    try std.testing.expect(!std.mem.eql(u8, &no_combo.digest, &(try protocol.computeIdentity(input)).digest));
}

test "identity preserves ordered combos encoders and callback declarations" {
    var input = base_input;
    input.dimensions.key_count = 2;
    input.keys = &.{ base_keys[0], null };
    input.sides = &.{ .L, .R };
    const first = model.Combo2Def{ .key_indexes = .{ 0, 1 }, .timeout = .{ .ms = 40 }, .layer = 0, .key_def = .none };
    const second = model.Combo2Def{ .key_indexes = .{ 1, 0 }, .timeout = .{ .ms = 50 }, .layer = 0, .key_def = base_keys[0].? };
    input.combos = &.{ first, second };
    const ordered_combos = (try protocol.computeIdentity(input)).digest;
    input.combos = &.{ second, first };
    try std.testing.expect(!std.mem.eql(u8, &ordered_combos, &(try protocol.computeIdentity(input)).digest));

    input.encoders = &.{ .{ .tap = .{ .custom = 253 } }, .{ .tap = .{ .custom = 255 } } };
    const ordered_encoders = (try protocol.computeIdentity(input)).digest;
    input.encoders = &.{ .{ .tap = .{ .custom = 255 } }, .{ .tap = .{ .custom = 253 } } };
    try std.testing.expect(!std.mem.eql(u8, &ordered_encoders, &(try protocol.computeIdentity(input)).digest));

    input.callbacks = &.{ .{ .id = 1, .behavior = "first-v1" }, .{ .id = 252, .behavior = "last-v1" } };
    const ordered_callbacks = (try protocol.computeIdentity(input)).digest;
    input.callbacks = &.{ .{ .id = 252, .behavior = "last-v1" }, .{ .id = 1, .behavior = "first-v1" } };
    try std.testing.expect(!std.mem.eql(u8, &ordered_callbacks, &(try protocol.computeIdentity(input)).digest));
    input.callbacks = &.{.{ .id = 253, .behavior = "reserved" }};
    try std.testing.expectError(error.InvalidCallback, protocol.computeIdentity(input));
    input.callbacks = &.{.{ .id = 1, .behavior = "" }};
    try std.testing.expectError(error.InvalidCallback, protocol.computeIdentity(input));
}

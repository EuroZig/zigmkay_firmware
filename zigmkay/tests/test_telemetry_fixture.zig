//! Synthetic processor fixture; no board wiring or published profile is copied.
const core = @import("zigmkay").core;
pub const dimensions = core.KeymapDimensions{ .key_count = 34, .layer_count = 4 };
pub const keymap: [4][34]?core.KeyDef = blk: {
    var keys: [4][34]?core.KeyDef = @splat(@splat(null));
    keys[0][0] = .{ .tap_only = .{ .key_press = .{ .tap_keycode = 4 } } };
    keys[0][30] = .{ .hold_only = .{ .hold_modifiers = .{ .left_shift = true } } };
    break :blk keys;
};
pub const sides: [34]core.Side = @splat(.L);
pub const combos: [0]core.Combo2Def = .{};
pub const custom_functions = core.CustomFunctions{};

pub fn identity(comptime protocol: type) protocol.Identity {
    return protocol.computeIdentity(.{
        .board_id = "fixture\x00".*,
        .profile_id = "typing\x00\x00".*,
        .dimensions = dimensions,
        .keys = @as([*]const ?core.KeyDef, @ptrCast(&keymap))[0 .. 34 * 4],
        .sides = &sides,
        .combos = &combos,
        .encoders = &.{},
        .callbacks = &.{},
    }) catch unreachable;
}

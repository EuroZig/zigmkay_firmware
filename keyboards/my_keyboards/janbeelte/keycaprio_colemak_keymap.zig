// Keycaprio (3x5+2) variant of the clackychan Colemak keymap. Layers, combos and
// custom functions come from the clackychan keymap and are remapped onto the
// 34-key matrix, so both boards share one layout.
const std = @import("std");

const zigmkay = @import("zigmkay");
pub const core = zigmkay.core;
const keycodes = @import("zkeycodes");
const us = keycodes.layouts.us_international;
const T = zigmkay.macros.T;

const clackychan = @import("clackychan_colemak_keymap.zig");

pub const key_count = 34;
// zig fmt: off
pub const sides = [key_count]core.Side{
  .L,.L,.L,.L,.L,       .R,.R,.R,.R,.R,
  .L,.L,.L,.L,.L,       .R,.R,.R,.R,.R,
  .L,.L,.L,.L,.L,       .R,.R,.R,.R,.R,
           .X,.X,       .X,.X
};
// zig fmt: on

// Keys the clackychan does not have.
const outer_bottom_left = 20;
const outer_bottom_right = 29;

/// Clackychan key index -> keycaprio key index. The clackychan lacks the outer
/// bottom pinky keys and has one thumb key per side (mapped to the inner ones).
fn remap(clackychan_index: usize) core.KeyIndex {
    return switch (clackychan_index) {
        0...19 => @intCast(clackychan_index),
        20...27 => @intCast(clackychan_index + 1),
        28 => 31,
        29 => 32,
        else => unreachable,
    };
}

pub const keymap = blk: {
    var result: [clackychan.keymap.len][key_count]?core.KeyDef = @splat(@splat(null));
    for (clackychan.keymap, 0..) |layer, layer_index| {
        for (layer, 0..) |key, key_index| {
            result[layer_index][remap(key_index)] = key;
        }
    }
    result[clackychan.L_BASE][outer_bottom_left] = T(us.Z);
    result[clackychan.L_BASE][outer_bottom_right] = T(us.SLSH);
    break :blk result;
};

pub const dimensions = core.KeymapDimensions{
    .key_count = key_count,
    .layer_count = keymap.len,
};

pub const combos = blk: {
    var result = clackychan.combos;
    for (&result) |*combo| {
        combo.key_indexes = .{ remap(combo.key_indexes[0]), remap(combo.key_indexes[1]) };
    }
    break :blk result;
};

pub const custom_functions = clackychan.custom_functions;

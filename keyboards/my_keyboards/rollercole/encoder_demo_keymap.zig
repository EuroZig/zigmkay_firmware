const core = @import("zigmkay").core;

pub const key_count = 1;
pub const keymap = [1][key_count]?core.KeyDef{.{.{ .tap_only = .{ .key_press = .{ .tap_keycode = 10 } } }}};
pub const dimensions = core.KeymapDimensions{ .key_count = key_count, .layer_count = keymap.len };
pub const encoder_actions = [_]core.EncoderAction{
    .{ .tap = .{ .media_key = .VolumeUp } },
    .{ .tap = .{ .media_key = .VolumeDown } },
};

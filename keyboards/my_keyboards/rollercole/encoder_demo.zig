const std = @import("std");

const microzig = @import("microzig");
comptime {
    microzig.export_startup();
}
pub const std_options = microzig.std_options(.{});
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const zigmkay = @import("zigmkay");
const dk = zigmkay.keycodes.dk;
const core = zigmkay.core;
const us = zigmkay.keycodes.us;
const time = rp2xxx.time;

const usb = zigmkay.usb;
const encoder_scanning = zigmkay.encoder_scanning;

// zig fmt: off
pub const pin_config = rp2xxx.pins.GlobalConfiguration{
    .GPIO17 = .{ .name = "led", .direction = .out },

    .GPIO0 = .{ .name = "col", .direction = .out },
    .GPIO1 = .{ .name = "row", .direction = .in },
    .GPIO23 = .{ .name = "data1", .direction = .in, .pull = .up, .function = .SIO },
    .GPIO21 = .{ .name = "data2", .direction = .in, .pull = .up , .function = .SIO},
    .GPIO8 = .{ .name = "click", .direction = .in, .pull = .up, .function = .SIO },
};
pub const p = pin_config.pins();

const supplied_keymap = @import("keymap");
const dimensions = @import("keymap_validation").validate(supplied_keymap, 1, null);
pub const no_pin_mappings = [dimensions.key_count]?[2]usize{ .{0,0} };

pub const scanner_settings = zigmkay.matrix_scanning.ScannerSettings{
    .debounce = .{ .ms = 50 },
};

// zig fmt: on
pub const pins_cols = [_]rp2xxx.gpio.Pin{p.col};
pub const pins_rows = [_]rp2xxx.gpio.Pin{p.row};

pub fn main() !void {
    run() catch {
        p.led.put(1);
    };
}

const default_encoder_actions = [_]core.EncoderAction{
    .{ .tap = core.TapDef{ .media_key = .VolumeUp } },
    .{ .tap = core.TapDef{ .media_key = .VolumeDown } },
};
var encoder_actions = @import("keymap_validation").encoderActions(supplied_keymap, default_encoder_actions);
var encoder_pin_configs = [_]encoder_scanning.EncoderPinConfig{encoder_scanning.EncoderPinConfig{
    .pin_a = p.data1,
    .pin_b = p.data2,
    .sensitivity = 4,
    .action_index_cw = 0,
    .action_index_ccw = 1,
}};
pub fn run() !void {
    _ = pin_config.apply();
    blink_led(1, 300); // Show the user that the keyboard has actually booted up.

    // Mandatory
    comptime var config = zigmkay.loops.GetUnibodyConfigType(&dimensions){
        .config = .{
            .keymap = &supplied_keymap.keymap,
            .companion_identity = @import("keymap_validation").companionIdentity(supplied_keymap, @import("firmware-options").companion_enabled),
            .scanner_settings = &.{
                .matrix = .{
                    .pin_cols = pins_cols[0..],
                    .pin_rows = pins_rows[0..],
                    .pins_to_keys_mapping = &no_pin_mappings,
                    .direction = .col2row,
                },
            },

            .encoder_pin_configs = encoder_pin_configs[0..],
            .encoder_actions = encoder_actions[0..],
        },
    };

    comptime var runner = config.build();
    runner.run_unibody() catch {
        blink_led(10000000, 500); // in case of an error, let the keyboard start blinking
    };
}

fn get_current_time() core.TimeSinceBoot {
    return core.TimeSinceBoot{
        .time_since_boot_us = time.get_time_since_boot().to_us(),
    };
}

pub fn blink_led(blink_count: u32, interval_ms: u32) void {
    var counter = blink_count;
    while (counter > 0) : (counter -= 1) {
        p.led.put(1);
        time.sleep_us(interval_ms * 1000);
        p.led.put(0);
        time.sleep_us(interval_ms * 1000);
    }
}

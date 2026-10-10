//! Portable payload shapes for the firmware's HID interfaces.
pub const KeyboardInReport = extern struct {
    modifiers: u8,
    reserved: u8 = 0,
    keys: [6]u8,

    pub const empty: @This() = .{ .modifiers = 0, .keys = @splat(0) };
};

pub const KeyboardOutReport = packed struct(u8) {
    num_lock: bool,
    caps_lock: bool,
    scroll_lock: bool,
    padding: u5 = 0,
};

pub const ConsumerInReport = extern struct {
    button: u16,

    pub const empty: @This() = .{ .button = 0 };
};

pub const MouseInReport = extern struct {
    buttons: u8,
    x: i8,
    y: i8,
    wheel: i8,
    pan: i8,

    pub const empty: @This() = .{ .buttons = 0, .x = 0, .y = 0, .wheel = 0, .pan = 0 };
};

//! Portable payload shapes for the firmware's HID interfaces.
//! Keyboard state adapted from GPL-2.0 reference 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
pub const KeyboardInReport = extern struct {
    modifiers: u8,
    reserved: u8 = 0,
    keys: [6]u8,

    pub const empty: @This() = .{ .modifiers = 0, .keys = @splat(0) };
};
pub const Keyboard = KeyboardInReport;

pub const KeyboardState = struct {
    pressed: [0xe0]bool = @splat(false),
    modifiers: u8 = 0,
    pub fn press(self: *@This(), usage: u8) void {
        if (usage >= 4 and usage < self.pressed.len) self.pressed[usage] = true;
    }
    pub fn release(self: *@This(), usage: u8) void {
        if (usage < self.pressed.len) self.pressed[usage] = false;
    }
    pub fn report(self: *const @This()) KeyboardInReport {
        var result = KeyboardInReport.empty;
        result.modifiers = self.modifiers;
        var count: usize = 0;
        for (self.pressed, 0..) |pressed, usage| {
            if (!pressed) continue;
            if (count == result.keys.len) {
                result.keys = @splat(1);
                return result;
            }
            result.keys[count] = @intCast(usage);
            count += 1;
        }
        return result;
    }
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

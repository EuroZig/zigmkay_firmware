// Compatibility entry point for consumers of the bounded flash wrapper.
const flash = @import("flash_picotool.zig");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    try flash.main(init);
}

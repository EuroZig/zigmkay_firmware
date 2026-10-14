//! HID definitions shared by the device and pinned-stack descriptor checks.
pub const usb = @import("microzig").core.usb;
pub const configuration = @import("usb_configuration.zig");
pub const wire = @import("usb_descriptor_bytes.zig");
pub const control = @import("usb_control.zig");
pub const requests = @import("usb_requests.zig");
pub const protocol = @import("device_protocol.zig");
pub const Transport = @import("telemetry_transport.zig").Transport;
const reports = @import("usb_reports.zig");
pub const KeyboardInReport = reports.KeyboardInReport;
pub const KeyboardOutReport = reports.KeyboardOutReport;

// HID Interrupt Driver for Standard Boot Keyboard
pub const Keyboard = usb.drivers.hid.InterruptDriver(.{
    .subclass = .Boot,
    .protocol = .Boot,
    .report_descriptor = &.{
        .{ .global_usage_page = .generic_desktop },
        .local_usage_enum(.{ .generic_desktop = .keyboard }),
        .{ .main_collection = .Application },
        // Input: modifier key bitmap
        .{ .data = .{
            .usage = .{ .global_page = .keyboard },
            .usage_range = .{ 0xE0, 0xE7 },
            .count = 8,
            .Child = bool,
            .dir = .in,
            .type = .dynamic,
        } },
        .{ .data_static = .{ .in, u8 } }, // Boot keyboard reserved byte
        // Input: up to 6 pressed key codes
        .{ .data = .{
            .usage = .{ .global_page = .keyboard },
            .usage_range = .{ 0x00, 0xff },
            .count = 6,
            .Child = u8,
            .dir = .in,
            .type = .selector,
        } },
        // Output: indicator LEDs
        .{ .data = .{
            .usage = .{ .global_page = .led },
            .usage_range = .{ 1, 5 },
            .count = 5,
            .Child = bool,
            .dir = .out,
            .type = .dynamic,
        } },
        // Padding
        .{ .data_static = .{ .out, u3 } },
        // End
        .main_collection_end,
    },
    .InReport = KeyboardInReport,
    .OutReport = KeyboardOutReport,
});

// Consumer Control (Media Keys)
pub const ConsumerInReport = reports.ConsumerInReport;

// HID Interrupt Driver for Consumer Control endpoints
pub const ConsumerControl = usb.drivers.hid.InterruptDriver(.{
    .subclass = .Unspecified,
    .protocol = .NoneRequired,
    .report_descriptor = &.{
        .{ .global_usage_page = @fromBackingInt(@intCast(0x0C)) }, // Consumer Page
        .{ .local_usage = 0x01 }, // Consumer Control
        .{ .main_collection = .Application },
        .{ .data = .{
            .usage = .{ .global_page = @fromBackingInt(@intCast(0x0C)) },
            .usage_range = .{ 0x00, 0x03FF },
            .count = 1,
            .Child = u16,
            .dir = .in,
            .type = .selector,
        } },
        .main_collection_end,
    },
    .InReport = ConsumerInReport,
    .OutReport = u8, // Dummy OutReport
});

// Mouse Implementation
pub const MouseInReport = reports.MouseInReport;

// HID Interrupt Driver for generic Mouse functionality
pub const Mouse = usb.drivers.hid.InterruptDriver(.{
    .subclass = .Unspecified,
    .protocol = .NoneRequired,
    .report_descriptor = &.{
        .{ .global_usage_page = .generic_desktop },
        .local_usage_enum(.{ .generic_desktop = @fromBackingInt(@intCast(0x02)) }), // Mouse
        .{ .main_collection = .Application },
        .{ .local_usage = 0x01 }, // Pointer
        .{ .main_collection = .Physical },
        .{
            .data = .{
                .usage = .{ .global_page = @fromBackingInt(@intCast(0x09)) }, // Button
                .usage_range = .{ 1, 5 },
                .count = 5,
                .Child = bool,
                .dir = .in,
                .type = .dynamic,
            },
        },
        .{ .data_static = .{ .in, u3 } }, // Padding
        .{ .global_usage_page = .generic_desktop },
        .{ .local_usage_min = 0x30 }, // X
        .{ .local_usage_max = 0x31 }, // Y
        .{ .global_logical_range = .{ -127, 127 } },
        .{ .global_report_count = 2 },
        .{ .global_report_size = 8 },
        .{ .main_input = .{ .variable = true, .relative = true } },
        // Wheel — must be Relative so the OS maps it to REL_WHEEL, not ABS_WHEEL
        .{ .local_usage = 0x38 },
        .{ .global_logical_range = .{ -127, 127 } },
        .{ .global_report_count = 1 },
        .{ .global_report_size = 8 },
        .{ .main_input = .{ .variable = true, .relative = true } },
        // Pan — same: Relative maps to REL_HWHEEL
        .{ .global_usage_page = @fromBackingInt(@intCast(0x0C)) }, // Consumer
        .{ .local_usage = 0x0238 },
        .{ .global_logical_range = .{ -127, 127 } },
        .{ .global_report_count = 1 },
        .{ .global_report_size = 8 },
        .{ .main_input = .{ .variable = true, .relative = true } },
        .main_collection_end,
        .main_collection_end,
    },
    .InReport = MouseInReport,
    .OutReport = u8, // Dummy
});

// RAWHID Implementation (QMK Style)
pub const RawHidReport = [32]u8;

// HID Interrupt Driver for the dedicated 32-byte bidirectional RAWHID channel (Companion App Telemetry)
pub const RawHid = @import("strict_rawhid.zig").Driver(usb.drivers.hid.InterruptDriver(.{
    .subclass = .Unspecified,
    .protocol = .NoneRequired,
    .report_descriptor = &.{
        .{ .global_usage_page = @fromBackingInt(@intCast(0xFF31)) }, // Vendor Page 0xFF31
        .{ .local_usage = 0x0074 }, // Usage 0x0074
        .{ .main_collection = .Application },
        // Input: 32 bytes
        .{ .data = .{
            .usage = .{ .local_raw = 0x01 },
            .count = 32,
            .Child = u8,
            .dir = .in,
            .type = .dynamic,
        } },
        // Output: 32 bytes
        .{ .data = .{
            .usage = .{ .local_raw = 0x02 },
            .count = 32,
            .Child = u8,
            .dir = .out,
            .type = .dynamic,
        } },
        .main_collection_end,
    },
    .InReport = RawHidReport,
    .OutReport = RawHidReport,
}));

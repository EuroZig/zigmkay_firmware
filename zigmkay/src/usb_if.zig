const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const usb = microzig.core.usb;
const USB_Device = rp2xxx.usb.Polled(.{});

pub const HID_KeymodifierCodes = enum(u8) {
    left_control = 0xe0,
    left_shift,
    left_alt,
    left_gui,
    right_control,
    right_shift,
    right_alt,
    right_gui,
};

const reports = @import("usb_reports.zig");
pub const KeyboardInReport = reports.KeyboardInReport;
pub const KeyboardOutReport = reports.KeyboardOutReport;

const descriptors = @import("usb_descriptors.zig");
const Keyboard = descriptors.Keyboard;
const ConsumerControl = descriptors.ConsumerControl;
const Mouse = descriptors.Mouse;
const RawHid = descriptors.RawHid;
pub const ConsumerInReport = reports.ConsumerInReport;
pub const MouseInReport = reports.MouseInReport;
pub const RawHidReport = descriptors.RawHidReport;

pub var usb_device: USB_Device = undefined;

pub const ControllerType = usb.DeviceController(.{
    .bcd_usb = .v2_00,
    .device_triple = .unspecified,
    .vendor = .{ .id = 0xFAFA, .str = "OpenKeyboardCollective" },
    .product = .{ .id = 0x00F0, .str = "ZigMkay" },
    // Keep this in sync with descriptor-set changes. Hosts cache HID report
    // descriptors by device identity, so changing the revision forces them to
    // enumerate newly added interfaces such as RawHID.
    .bcd_device = .v1_11,
    .serial = "00000001",
    .max_supported_packet_size = USB_Device.max_supported_packet_size,
    .configurations = &.{.{
        .attributes = .{ .self_powered = false },
        .max_current_ma = 500,
        .Drivers = struct {
            keyboard: Keyboard,
            consumer: ConsumerControl,
            mouse: Mouse,
            rawhid: RawHid,
            reset: rp2xxx.usb.ResetDriver(null, 0),
        },
    }},
}, .{.{
    .keyboard = .{ .itf_string = "Keyboard", .poll_interval = 1 },
    .consumer = .{ .itf_string = "Consumer Control", .poll_interval = 10 },
    .mouse = .{ .itf_string = "Mouse", .poll_interval = 1 },
    .rawhid = .{ .itf_string = "RawHID", .poll_interval = 1 },
    .reset = "",
}});

pub var usb_controller: ControllerType = .init;

pub fn init() void {
    usb_device = .init();
}

pub fn poll() void {
    usb_device.poll(&usb_controller);
}

/// Dispatches a keyboard report over the first HID interface
pub fn send_keyboard_report(report: *const KeyboardInReport) void {
    if (usb_controller.drivers()) |drivers| {
        _ = drivers.keyboard.send_report(report);
    }
}

/// Dispatches a consumer layout report (Media Keys)
pub fn send_consumer_report(report: *const ConsumerInReport) void {
    if (usb_controller.drivers()) |drivers| {
        _ = drivers.consumer.send_report(report);
    }
}

/// Dispatches a mouse payload containing movement or clicks
pub fn send_mouse_report(report: *const MouseInReport) void {
    if (usb_controller.drivers()) |drivers| {
        _ = drivers.mouse.send_report(report);
    }
}

/// Pushes a custom 32-byte payload to the RAWHID interface for companion app signalling
pub fn send_raw_report(report: *const RawHidReport) void {
    if (usb_controller.drivers()) |drivers| {
        _ = drivers.rawhid.send_report(report);
    }
}

pub fn receive_raw_report() ?RawHidReport {
    if (usb_controller.drivers()) |drivers| return drivers.rawhid.receive_report();
    return null;
}

pub fn raw_connected() bool {
    return usb_controller.drivers() != null;
}

pub fn try_send_raw_report(_: *anyopaque, report: *const RawHidReport) bool {
    if (usb_controller.drivers()) |drivers| return drivers.rawhid.send_report(report);
    return false;
}

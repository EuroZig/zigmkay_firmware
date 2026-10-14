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

const usb_config: usb.Config = .{
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
};
const usb_args: usb_config.DriverArgs() = .{.{
    .keyboard = .{ .itf_string = "Keyboard", .poll_interval = 1 },
    .consumer = .{ .itf_string = "Consumer Control", .poll_interval = 10 },
    .mouse = .{ .itf_string = "Mouse", .poll_interval = 1 },
    .rawhid = .{ .itf_string = "RawHID", .poll_interval = 1 },
    .reset = "",
}};
pub const ControllerType = usb.DeviceController(usb_config, usb_args);

pub var usb_controller: ControllerType = .init;
const control = @import("usb_control.zig");
const requests = @import("usb_requests.zig");
const Wire = @import("usb_configuration.zig").descriptors(usb, usb_config, usb_args);
var initializer = @import("usb_driver_init.zig").Initializer(usb, usb_config, usb_args){};
var request_state = requests.Device{
    .device_descriptor = &Wire.device,
    .configuration_descriptor = &Wire.configuration,
    .strings = &Wire.strings,
    .hid_descriptors = &Wire.hid,
    .report_descriptors = &Wire.reports,
    .endpoints = &Wire.endpoints,
    .vendor_interface = Wire.vendor_interface.?,
    .interface_count = Wire.configuration[4],
    .hooks = .{ .configure = configure_drivers, .address = set_address, .halt = endpoint_halt, .vendor_output = receive_vendor, .alternate = reset_alternate },
};
var controller = control.Controller(usb, ControllerType){
    .base = &usb_controller,
    .hooks = .{ .prepare = prepare_control, .reject = reject_control, .request = handle_request, .output = receive_control, .status_complete = status_complete, .reset = reset_requests },
};
var boundary_failed = false;
var pending_bootsel = false;
var configuration_epoch: u32 = 0;
var last_input_ms: [4]u64 = @splat(0);

fn handle_request(setup: control.Setup) @import("usb_ep0.zig").Reply {
    // Preserve the existing reset interface, committing only after status IN.
    if (setup.request_type == 0x41 and (setup.request == 1 or setup.request == 2) and
        setup.index == Wire.reset_interface.? and setup.length == 0 and request_state.configuration == 1)
    {
        pending_bootsel = true;
        return .ack;
    }
    const reply = request_state.setup(setup);
    return if (boundary_failed) .reject else reply;
}

fn receive_control(bytes: []const u8) bool {
    return request_state.receiveOutput(bytes);
}
fn receive_vendor(bytes: []const u8) void {
    if (controller.telemetry) |transport| transport.receive(bytes);
}
fn status_complete() void {
    request_state.statusComplete();
    if (pending_bootsel) rp2xxx.rom.reset_to_usb_boot();
}
fn set_address(address: u7) void {
    usb_device.interface.set_address(address);
}
fn reset_requests() void {
    boundary_failed = false;
    pending_bootsel = false;
    request_state.reset();
}

const buffers = @import("usb_buffer_control.zig");
const BufferHardware = struct {
    pub fn active(_: *@This(), mask: u32) u32 {
        const controls: *volatile [32]u32 = @ptrCast(&microzig.chip.peripherals.USB_DPRAM.EP0_IN_BUFFER_CONTROL);
        var owned: u32 = 0;
        for (0..32) |bit| {
            const flag = @as(u32, 1) << @intCast(bit);
            if (mask & flag != 0 and controls[bit] & buffers.available != 0) owned |= flag;
        }
        return owned;
    }
    pub fn revision(_: *@This()) u4 {
        return microzig.chip.peripherals.SYSINFO.CHIP_ID.read().REVISION;
    }
    pub fn abort(_: *@This(), mask: u32) void {
        microzig.chip.peripherals.USB.EP_ABORT.raw |= mask;
    }
    pub fn done(_: *@This()) u32 {
        return microzig.chip.peripherals.USB.EP_ABORT_DONE.raw;
    }
    pub fn now(_: *@This()) u64 {
        return rp2xxx.time.get_time_since_boot().to_us();
    }
};
fn begin_revoke(mask: u32) bool {
    var hardware = BufferHardware{};
    buffers.revoke(&hardware, mask) catch {
        boundary_failed = true;
        return false;
    };
    return true;
}
fn end_revoke(mask: u32) void {
    const peripheral = microzig.chip.peripherals;
    peripheral.USB.EP_ABORT_DONE.raw = buffers.abortDoneAck(mask);
    peripheral.USB.EP_ABORT.raw &= ~mask;
}
fn prepare_control() bool {
    request_state.cancel();
    pending_bootsel = false;
    if (boundary_failed or !begin_revoke(3)) return false;
    const peripheral = microzig.chip.peripherals;
    peripheral.USB.BUFF_STATUS.raw = 3;
    peripheral.USB_DPRAM.EP0_IN_BUFFER_CONTROL.raw = buffers.prepareSetup(peripheral.USB_DPRAM.EP0_IN_BUFFER_CONTROL.raw);
    peripheral.USB_DPRAM.EP0_OUT_BUFFER_CONTROL.raw = buffers.prepareSetup(peripheral.USB_DPRAM.EP0_OUT_BUFFER_CONTROL.raw);
    peripheral.USB.EP_STALL_ARM.modify(.{ .EP0_IN = 0, .EP0_OUT = 0 });
    end_revoke(3);
    return true;
}
fn reject_control() void {
    if (boundary_failed) return;
    const peripheral = microzig.chip.peripherals;
    peripheral.USB.EP_STALL_ARM.modify(.{ .EP0_IN = 1, .EP0_OUT = 1 });
    peripheral.USB_DPRAM.EP0_IN_BUFFER_CONTROL.modify(.{ .STALL = 1 });
    peripheral.USB_DPRAM.EP0_OUT_BUFFER_CONTROL.modify(.{ .STALL = 1 });
}
fn configure_drivers(number: u16) void {
    if (!begin_revoke(0xfffffffc)) return;
    const peripheral = microzig.chip.peripherals;
    const controls: *volatile [30]u32 = @ptrCast(&peripheral.USB_DPRAM.EP1_IN_CONTROL);
    const buffer_controls: *volatile [30]u32 = @ptrCast(&peripheral.USB_DPRAM.EP1_IN_BUFFER_CONTROL);
    for (0..30) |i| {
        controls[i] = 0;
        buffer_controls[i] = 0;
    }
    peripheral.USB.BUFF_STATUS.raw = 0xfffffffc;
    end_revoke(0xfffffffc);
    const arena: [*]align(64) u8 = @ptrFromInt(@intFromPtr(peripheral.USB_DPRAM) + 0x180);
    usb_device.data_buffer = arena[0..3712];
    initializer.configure(&usb_controller, &usb_device.interface, number);
    configuration_epoch +%= 1;
    last_input_ms = @splat(0);
}
fn endpoint_halt(address: u8, change: ?bool) bool {
    const peripheral = microzig.chip.peripherals;
    const bit: u5 = @intCast((address & 0xf) * 2 + @intFromBool(address & 0x80 == 0));
    const controls: *volatile [32]u32 = @ptrCast(&peripheral.USB_DPRAM.EP0_IN_BUFFER_CONTROL);
    if (change) |halted| {
        const mask = @as(u32, 1) << bit;
        if (!begin_revoke(mask)) return true;
        if (halted) controls[bit] |= buffers.stall else {
            controls[bit] = buffers.pid;
            peripheral.USB.BUFF_STATUS.raw = mask;
        }
        end_revoke(mask);
        if (!halted) {
            if (usb_controller.drivers()) |drivers| {
                inline for (.{ "keyboard", "consumer", "mouse", "rawhid" }) |name| {
                    const driver = &@field(drivers, name);
                    const base = if (comptime std.mem.eql(u8, name, "rawhid")) &driver.base else driver;
                    if (address & 0x80 != 0 and @backingInt(base.descriptor.ep_in.endpoint.num) == address & 0xf)
                        base.tx_ready.store(true, .seq_cst);
                    if (address & 0x80 == 0 and @backingInt(base.descriptor.ep_out.endpoint.num) == address & 0xf) {
                        base.rx_ready.store(false, .seq_cst);
                        usb_device.interface.ep_listen(base.descriptor.ep_out.endpoint.num, @intCast(base.descriptor.ep_out.max_packet_size.native()));
                    }
                }
            }
        }
    }
    return controls[bit] & buffers.stall != 0;
}

fn reset_alternate(interface: u8) void {
    if (interface >= Wire.hid.len) return;
    _ = endpoint_halt(Wire.endpoints[@as(usize, interface) * 2], false);
    _ = endpoint_halt(Wire.endpoints[@as(usize, interface) * 2 + 1], false);
}

pub fn attach_telemetry(transport: *@import("telemetry_transport.zig").Transport) void {
    controller.telemetry = transport;
}

pub fn init() void {
    usb_controller = .init;
    controller.telemetry = null;
    controller.transfer.reset();
    controller.ready = true;
    request_state.cancel();
    request_state.address = 0;
    request_state.configuration = 0;
    boundary_failed = false;
    pending_bootsel = false;
    usb_device = .init();
}

pub fn poll() void {
    usb_device.poll(&controller);
    if (boundary_failed) return;
    if (usb_controller.drivers()) |drivers| {
        // The stock helper loses the received length, including for LED output.
        if (drivers.keyboard.rx_ready.swap(false, .seq_cst)) {
            var bytes: [64]u8 = @splat(0);
            const endpoint = drivers.keyboard.descriptor.ep_out;
            const length = usb_device.interface.ep_readv(endpoint.endpoint.num, &.{&bytes});
            usb_device.interface.ep_listen(endpoint.endpoint.num, @intCast(endpoint.max_packet_size.native()));
            if (length == 1) _ = request_state.interruptOutput(0, bytes[0..1]);
        }
    }
    _ = receive_raw_report();
}

/// Dispatches a keyboard report over the first HID interface
pub fn send_keyboard_report(report: *const KeyboardInReport) bool {
    if (boundary_failed) return false;
    if (usb_controller.drivers()) |drivers| {
        if (!drivers.keyboard.send_report(report)) return false;
        record_input(0, std.mem.asBytes(report));
        return true;
    }
    return false;
}

/// Dispatches a consumer layout report (Media Keys)
pub fn send_consumer_report(report: *const ConsumerInReport) bool {
    if (boundary_failed) return false;
    if (usb_controller.drivers()) |drivers| {
        if (!drivers.consumer.send_report(report)) return false;
        record_input(1, std.mem.asBytes(report));
        return true;
    }
    return false;
}

/// Dispatches a mouse payload containing movement or clicks
pub fn send_mouse_report(report: *const MouseInReport) bool {
    if (boundary_failed) return false;
    if (usb_controller.drivers()) |drivers| {
        if (!drivers.mouse.send_report(report)) return false;
        record_input(2, std.mem.asBytes(report));
        return true;
    }
    return false;
}

/// Pushes a custom 32-byte payload to the RAWHID interface for companion app signalling
pub fn send_raw_report(report: *const RawHidReport) bool {
    if (boundary_failed) return false;
    if (usb_controller.drivers()) |drivers| {
        if (!drivers.rawhid.send_report(report)) return false;
        record_input(3, report);
        return true;
    }
    return false;
}

pub fn receive_raw_report() ?RawHidReport {
    if (usb_controller.drivers()) |drivers| {
        if (drivers.rawhid.receive_report()) |report| {
            _ = request_state.interruptOutput(Wire.vendor_interface.?, &report);
            return report;
        }
    }
    return null;
}

pub fn raw_connected() bool {
    return !boundary_failed and usb_controller.drivers() != null;
}

pub fn try_send_raw_report(_: *anyopaque, report: *const RawHidReport) bool {
    return send_raw_report(report);
}

pub const configured = raw_connected;
pub fn configuration_generation() u32 {
    return configuration_epoch;
}
fn record_input(index: usize, bytes: []const u8) void {
    request_state.recordInput(@intCast(index), bytes);
    last_input_ms[index] = rp2xxx.time.get_time_since_boot().to_us() / 1000;
}
pub fn idle(pending: [4]bool) void {
    if (!configured()) return;
    const now = rp2xxx.time.get_time_since_boot().to_us() / 1000;
    if (!pending[0] and request_state.idleDue(0, now, last_input_ms[0])) {
        const bytes = &request_state.input[0];
        const report = KeyboardInReport{ .modifiers = bytes[0], .reserved = 0, .keys = bytes[2..8].* };
        _ = send_keyboard_report(&report);
    }
    if (!pending[1] and request_state.idleDue(1, now, last_input_ms[1])) {
        const report = ConsumerInReport{ .button = std.mem.readInt(u16, request_state.input[1][0..2], .little) };
        _ = send_consumer_report(&report);
    }
    // Repeating a mouse displacement or v2 delta would replay an action.
}

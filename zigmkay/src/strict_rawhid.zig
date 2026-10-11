//! Preserve the pinned HID descriptor while rejecting truncated OUT reports.
const std = @import("std");
const usb = @import("microzig").core.usb;

pub fn Driver(comptime Base: type) type {
    return struct {
        const Self = @This();
        pub const Descriptor = Base.Descriptor;
        pub const report_descriptor = Base.report_descriptor;
        pub const handlers: usb.DriverHandlers(Self) = .{
            .ep_in = on_tx_ready,
            .ep_out = on_rx,
        };
        base: Base,

        pub fn init(self: *Self, descriptor: *const Descriptor, device: *usb.DeviceInterface) void {
            self.base.init(descriptor, device);
        }

        pub fn class_request(self: *Self, setup: *const usb.types.SetupPacket) ?[]const u8 {
            // The pinned controller cannot deliver EP0 OUT data to a driver.
            // Never acknowledge a command that cannot reach the application.
            if (setup.request_type.type == .class and setup.request == 0x09) return usb.nak;
            return self.base.class_request(setup);
        }

        pub fn on_tx_ready(self: *Self, ep: usb.types.Endpoint.Num) void {
            self.base.on_tx_ready(ep);
        }

        pub fn on_rx(self: *Self, ep: usb.types.Endpoint.Num) void {
            self.base.on_rx(ep);
        }

        pub fn send_report(self: *Self, report: *const [32]u8) bool {
            return self.base.send_report(report);
        }

        pub fn receive_report(self: *Self) ?[32]u8 {
            if (!self.base.rx_ready.swap(false, .seq_cst)) return null;
            var report: [32]u8 = @splat(0);
            const ep = self.base.descriptor.ep_out.endpoint.num;
            const len = self.base.device.ep_readv(ep, &.{std.mem.asBytes(&report)});
            self.base.device.ep_listen(ep, @intCast(self.base.descriptor.ep_out.max_packet_size.native()));
            if (len != report.len) return null;
            return report;
        }
    };
}

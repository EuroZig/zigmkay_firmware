//! Firmware-owned control transfer dispatch; no host/application dependencies.
//! Adapted from the GPL-2.0 reference at 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
const ep0 = @import("usb_ep0.zig");
const Transport = @import("telemetry_transport.zig").Transport;
pub const Setup = ep0.Setup;
pub const SetupReply = ep0.Reply;

pub const Hooks = struct {
    /// Cancel old hardware buffers and initialize both directions for DATA1.
    prepare: *const fn () bool,
    reject: *const fn () void,
    request: *const fn (Setup) ep0.Reply,
    output: *const fn ([]const u8) bool,
    status_complete: *const fn () void,
    reset: *const fn () void,
};

pub fn Controller(comptime usb: type, comptime Base: type) type {
    return struct {
        const Self = @This();
        base: *Base,
        hooks: Hooks,
        telemetry: ?*Transport = null,
        transfer: ep0.Transfer = .{},
        ready: bool = true,

        pub fn on_setup_req(self: *Self, device: *usb.DeviceInterface, packet: *const usb.types.SetupPacket) void {
            self.transfer.reset();
            self.base.tx_slice = null;
            self.base.new_address = 0;
            self.ready = self.hooks.prepare();
            if (!self.ready) return;
            const setup = Setup{
                .request_type = @bitCast(packet.request_type),
                .request = packet.request,
                .value = packet.value.native(),
                .index = packet.index.native(),
                .length = packet.length.native(),
            };
            // Configuration changes are session boundaries even when the final
            // driver pointer still exists (reselecting the same configuration).
            const reply = self.hooks.request(setup);
            if (setup.request_type == 0 and setup.request == 9 and reply == .ack)
                if (self.telemetry) |transport| {
                    transport.disconnect();
                };
            self.transfer.setup(device, setup, reply, self.hooks.reject);
        }

        pub fn on_buffer(self: *Self, device: *usb.DeviceInterface, comptime endpoint: usb.types.Endpoint) void {
            if (!self.ready) return;
            if (comptime endpoint.num == .ep0) {
                if (comptime endpoint.dir == .in) {
                    if (self.transfer.inComplete(device)) self.hooks.status_complete();
                } else self.transfer.outComplete(device, self.hooks.output, self.hooks.reject);
                return;
            }
            // Stale completions after reset/deconfiguration have no driver.
            if (self.base.drivers() != null) self.base.on_buffer(device, endpoint);
        }

        pub fn on_bus_reset(self: *Self, device: *usb.DeviceInterface) void {
            self.transfer.reset();
            if (self.telemetry) |transport| transport.disconnect();
            self.hooks.reset();
            self.base.on_bus_reset(device);
            self.ready = true;
        }
    };
}

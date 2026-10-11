const std = @import("std");
const descriptors = @import("usb_descriptors");
const usb = descriptors.usb;

const Fake = struct {
    interface: usb.DeviceInterface = .{ .vtable = &vtable },
    length: usb.types.Len = 32,
    reads: usize = 0,
    listens: usize = 0,
    writes: usize = 0,
    const vtable: usb.DeviceInterface.VTable = .{
        .ep_writev = write,
        .ep_readv = read,
        .ep_listen = listen,
        .ep_open = open,
        .set_address = address,
    };
    fn from(interface: *usb.DeviceInterface) *Fake {
        return @fieldParentPtr("interface", interface);
    }
    fn write(interface: *usb.DeviceInterface, _: usb.types.Endpoint.Num, data: []const []const u8) usb.types.Len {
        from(interface).writes += 1;
        return @intCast(data[0].len);
    }
    fn read(interface: *usb.DeviceInterface, _: usb.types.Endpoint.Num, data: []const []u8) usb.types.Len {
        const self = from(interface);
        self.reads += 1;
        @memset(data[0][0..self.length], 0x5a);
        return self.length;
    }
    fn listen(interface: *usb.DeviceInterface, _: usb.types.Endpoint.Num, _: usb.types.Len) void {
        from(interface).listens += 1;
    }
    fn open(_: *usb.DeviceInterface, _: *const usb.descriptor.Endpoint) void {}
    fn address(_: *usb.DeviceInterface, _: u7) void {}
};

test "RawHID rejects every short interrupt report and always rearms" {
    var fake = Fake{};
    var descriptor: descriptors.RawHid.Descriptor = undefined;
    descriptor.ep_out = .interrupt(@fromBackingInt(1), 32, 1);
    descriptor.ep_in = .interrupt(@fromBackingInt(2), 32, 1);
    var driver: descriptors.RawHid = undefined;
    driver.init(&descriptor, &fake.interface);
    var setup: usb.types.SetupPacket = @bitCast(@as(u64, 0));
    setup.request_type.type = .class;
    setup.request = 0x09;
    setup.length = .from(32);
    try std.testing.expectEqual(usb.nak, driver.class_request(&setup));
    for (0..32) |len| {
        fake.length = @intCast(len);
        driver.on_rx(descriptor.ep_out.endpoint.num);
        try std.testing.expect(driver.receive_report() == null);
        try std.testing.expect(driver.receive_report() == null);
    }
    fake.length = 32;
    driver.on_rx(descriptor.ep_out.endpoint.num);
    try std.testing.expectEqual(@as([32]u8, @splat(0x5a)), driver.receive_report().?);
    try std.testing.expectEqual(@as(usize, 33), fake.reads);
    try std.testing.expectEqual(@as(usize, 34), fake.listens);
    const report: [32]u8 = @splat(0);
    try std.testing.expect(driver.send_report(&report));
    try std.testing.expect(!driver.send_report(&report));
    try std.testing.expectEqual(@as(usize, 1), fake.writes);
}

test "pinned serializer emits reserved keyboard byte before key array" {
    const expected = [_]u8{ 0x95, 8, 0x75, 1, 0x81, 2, 0x95, 1, 0x75, 8, 0x81, 1, 0x05, 7 };
    try std.testing.expect(std.mem.indexOf(u8, descriptors.Keyboard.report_descriptor, &expected) != null);
}

test "pinned serializer emits relative X Y wheel and pan" {
    const xy = [_]u8{ 0x19, 0x30, 0x29, 0x31, 0x15, 0x81, 0x25, 0x7f, 0x95, 2, 0x75, 8, 0x81, 6 };
    try std.testing.expect(std.mem.indexOf(u8, descriptors.Mouse.report_descriptor, &xy) != null);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, descriptors.Mouse.report_descriptor, &.{ 0x81, 6 }));
}

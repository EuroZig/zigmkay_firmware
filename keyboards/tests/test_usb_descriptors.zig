const std = @import("std");
const descriptors = @import("usb_descriptors");
const usb = descriptors.usb;

const Fake = struct {
    interface: usb.DeviceInterface = .{ .vtable = &vtable },
    length: usb.types.Len = 32,
    incoming: [64]u8 = @splat(0x5a),
    reads: usize = 0,
    listens: usize = 0,
    writes: usize = 0,
    outgoing: [256]u8 = @splat(0),
    outgoing_length: usize = 0,
    stream: [256]u8 = @splat(0),
    stream_length: usize = 0,
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
        const self = from(interface);
        self.writes += 1;
        self.outgoing_length = @min(data[0].len, 64);
        @memcpy(self.outgoing[0..self.outgoing_length], data[0][0..self.outgoing_length]);
        const retained = @min(self.outgoing_length, self.stream.len - self.stream_length);
        @memcpy(self.stream[self.stream_length..][0..retained], data[0][0..retained]);
        self.stream_length += retained;
        return @intCast(self.outgoing_length);
    }
    fn read(interface: *usb.DeviceInterface, _: usb.types.Endpoint.Num, data: []const []u8) usb.types.Len {
        const self = from(interface);
        self.reads += 1;
        const length = @min(data[0].len, self.length);
        @memcpy(data[0][0..length], self.incoming[0..length]);
        return @intCast(length);
    }
    fn listen(interface: *usb.DeviceInterface, _: usb.types.Endpoint.Num, _: usb.types.Len) void {
        from(interface).listens += 1;
    }
    fn open(_: *usb.DeviceInterface, _: *const usb.descriptor.Endpoint) void {}
    fn address(_: *usb.DeviceInterface, _: u7) void {}
};

const config: usb.Config = .{
    .bcd_usb = .v2_00,
    .device_triple = .unspecified,
    .vendor = .{ .id = 0xFAFA, .str = "OpenKeyboardCollective" },
    .product = .{ .id = 0x00F0, .str = "ZigMkay" },
    .bcd_device = .v1_11,
    .serial = "test",
    .max_supported_packet_size = 64,
    .configurations = &.{.{
        .attributes = .{ .self_powered = false },
        .max_current_ma = 500,
        .Drivers = struct { keyboard: descriptors.Keyboard, consumer: descriptors.ConsumerControl, mouse: descriptors.Mouse, rawhid: descriptors.RawHid },
    }},
};
const args: config.DriverArgs() = .{.{
    .keyboard = .{ .poll_interval = 1 },
    .consumer = .{ .poll_interval = 10 },
    .mouse = .{ .poll_interval = 1 },
    .rawhid = .{ .poll_interval = 1 },
}};
const Base = usb.DeviceController(config, args);
const Wire = descriptors.configuration.descriptors(usb, config, args);
const Wrapper = descriptors.control.Controller(usb, Base);
const identity: descriptors.protocol.Identity = .{
    .board_id = .{ 'f', 'i', 'x', 't', 'u', 'r', 'e', 0 },
    .profile_id = .{ 'c', 'o', 'n', 't', 'r', 'o', 'l', 0 },
    .digest = @splat(1),
    .dimensions = .{ .key_count = 1, .layer_count = 1 },
};
const Capture = struct {
    var base: Base = .init;
    var fake = Fake{};
    var initializer: descriptors.configuration.Initializer(usb, config, args) = .{};
    var transport = descriptors.Transport.init(identity);
    var rejects: usize = 0;
    var prepares: usize = 0;
    var outputs: usize = 0;
    var allow_prepare = true;
    var state: descriptors.requests.Device = undefined;
    fn prepare() bool {
        state.cancel();
        prepares += 1;
        return allow_prepare;
    }
    fn reject() void {
        rejects += 1;
    }
    fn request(packet: descriptors.control.Setup) @import("usb_descriptors").control.SetupReply {
        return state.setup(packet);
    }
    fn output(bytes: []const u8) bool {
        return state.receiveOutput(bytes);
    }
    fn status() void {
        state.statusComplete();
    }
    fn reset() void {
        state.reset();
    }
    fn configure(number: u16) void {
        initializer.configure(&base, &fake.interface, number);
    }
    fn address(_: u7) void {}
    fn halt(_: u8, _: ?bool) bool {
        return false;
    }
    fn vendor(bytes: []const u8) void {
        outputs += 1;
        transport.receive(bytes);
    }
    fn init() Wrapper {
        base = .init;
        fake = .{};
        rejects = 0;
        prepares = 0;
        outputs = 0;
        allow_prepare = true;
        transport = descriptors.Transport.init(identity);
        state = .{ .device_descriptor = &Wire.device, .configuration_descriptor = &Wire.configuration, .strings = &Wire.strings, .hid_descriptors = &Wire.hid, .report_descriptors = &Wire.reports, .endpoints = &Wire.endpoints, .address = 12, .hooks = .{ .configure = configure, .address = address, .halt = halt, .vendor_output = vendor } };
        _ = state.setup(.{ .request_type = 0, .request = 9, .value = 1, .index = 0, .length = 0 });
        return .{ .base = &base, .telemetry = &transport, .hooks = .{ .prepare = prepare, .reject = reject, .request = request, .output = output, .status_complete = status, .reset = reset } };
    }
};

fn setup(raw: u8, request: u8, value: u16, index: u16, length: u16) usb.types.SetupPacket {
    return .{ .request_type = @bitCast(raw), .request = request, .value = .from(value), .index = .from(index), .length = .from(length) };
}

test "wrapper delivers SetReport once and commits status only after the data" {
    var wrapper = Capture.init();
    const bytes = try descriptors.protocol.encodePacket(.{ .session = 0, .nonce = 42, .request = 1, .payload = .hello }, identity.dimensions, .host_to_device);
    @memcpy(Capture.fake.incoming[0..32], &bytes);
    const packet = setup(0x21, 9, 0x0200, Capture.initializer.descriptors[3].interface.interface_number, 32);
    wrapper.on_setup_req(&Capture.fake.interface, &packet);
    try std.testing.expectEqual(@as(usize, 0), Capture.fake.writes);
    wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .out });
    try std.testing.expectEqual(@as(usize, 1), Capture.outputs);
    try std.testing.expectEqual(@as(usize, 1), Capture.fake.writes);
    wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .out });
    try std.testing.expectEqual(@as(usize, 1), Capture.outputs);
    wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .in });
    Capture.transport.boundary();
    try std.testing.expectEqual(@as(u32, 42), Capture.transport.session);
}

test "wrapper rejects every malformed data length and recovers on a new setup" {
    var wrapper = Capture.init();
    const packet = setup(0x21, 9, 0x0200, 3, 32);
    for (0..65) |len| {
        if (len == 32) continue;
        wrapper.on_setup_req(&Capture.fake.interface, &packet);
        Capture.fake.length = @intCast(len);
        wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .out });
    }
    try std.testing.expectEqual(@as(usize, 64), Capture.rejects);
    try std.testing.expectEqual(@as(usize, 0), Capture.outputs);
    wrapper.on_setup_req(&Capture.fake.interface, &packet);
    Capture.fake.length = 32;
    wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .out });
    try std.testing.expectEqual(@as(usize, 1), Capture.outputs);
}

test "wrapper cancels old output and descriptor state and disconnects on reset or reconfiguration" {
    var wrapper = Capture.init();
    const output_packet = setup(0x21, 9, 0x0200, 3, 32);
    const descriptor_packet = setup(0x80, 6, 0x0200, 0, 255);
    wrapper.on_setup_req(&Capture.fake.interface, &output_packet);
    wrapper.on_setup_req(&Capture.fake.interface, &descriptor_packet);
    wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .out });
    try std.testing.expectEqual(@as(usize, 0), Capture.outputs);
    const address_packet = setup(0, 5, 22, 0, 0);
    const deconfigure = setup(0, 9, 0, 0, 0);
    wrapper.on_setup_req(&Capture.fake.interface, &deconfigure);
    wrapper.on_setup_req(&Capture.fake.interface, &address_packet);
    wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .in });
    try std.testing.expectEqual(@as(u7, 22), Capture.state.address);
    const configure = setup(0, 9, 1, 0, 0);
    Capture.transport.session = 42;
    Capture.transport.state.pressed[0] = 1;
    wrapper.on_setup_req(&Capture.fake.interface, &configure);
    try std.testing.expectEqual(@as(u32, 0), Capture.transport.session);
    Capture.transport.session = 43;
    wrapper.on_setup_req(&Capture.fake.interface, &configure);
    try std.testing.expectEqual(@as(u32, 0), Capture.transport.session);
    wrapper.on_setup_req(&Capture.fake.interface, &output_packet);
    wrapper.on_bus_reset(&Capture.fake.interface);
    wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .out });
    try std.testing.expectEqual(@as(usize, 0), Capture.outputs);
    try std.testing.expectEqual(@as(u8, 1), Capture.transport.state.pressed[0]);
    try std.testing.expect(Capture.base.drivers() == null);
}

test "wrapper completes descriptor status OUT and fails closed when preparation fails" {
    var wrapper = Capture.init();
    const packet = setup(0x80, 6, 0x0200, 0, 255);
    const listens = Capture.fake.listens;
    wrapper.on_setup_req(&Capture.fake.interface, &packet);
    for (0..3) |_| wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .in });
    try std.testing.expectEqual(listens + 1, Capture.fake.listens);
    Capture.fake.length = 0;
    wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .out });
    const writes = Capture.fake.writes;
    Capture.allow_prepare = false;
    wrapper.on_setup_req(&Capture.fake.interface, &packet);
    wrapper.on_buffer(&Capture.fake.interface, .{ .num = .ep0, .dir = .in });
    try std.testing.expectEqual(writes, Capture.fake.writes);
    try std.testing.expect(!wrapper.ready);
}

test "pinned controller leaves descriptor status OUT unarmed and GetConfiguration unanswered" {
    std.testing.log_level = .err;
    defer std.testing.log_level = .warn;
    var fake = Fake{};
    var base: Base = .init;
    const get_device = setup(0x80, 6, 0x0100, 0, 18);
    base.on_setup_req(&fake.interface, &get_device);
    try std.testing.expectEqual(@as(usize, 18), fake.outgoing_length);
    base.on_buffer(&fake.interface, .{ .num = .ep0, .dir = .in });
    try std.testing.expectEqual(@as(usize, 0), fake.listens);
    const get_configuration = setup(0x80, 8, 0, 0, 1);
    base.cfg_num = 1;
    base.on_setup_req(&fake.interface, &get_configuration);
    try std.testing.expectEqual(@as(usize, 1), fake.writes);
}

test "pinned HID acknowledges SetReport without listening or consuming control OUT" {
    std.testing.log_level = .err;
    defer std.testing.log_level = .warn;
    var fake = Fake{};
    var base: Base = .init;
    var initializer: descriptors.configuration.Initializer(usb, config, args) = .{};
    initializer.configure(&base, &fake.interface, 1);
    const listens = fake.listens;
    const packet = setup(0x21, 9, 0x0200, 0, 1);
    base.on_setup_req(&fake.interface, &packet);
    try std.testing.expectEqual(@as(usize, 1), fake.writes);
    try std.testing.expectEqual(@as(usize, 0), fake.outgoing_length);
    try std.testing.expectEqual(listens, fake.listens);
    base.on_buffer(&fake.interface, .{ .num = .ep0, .dir = .out });
    try std.testing.expectEqual(@as(usize, 0), fake.reads);
}

test "pinned new setup retains a previous descriptor remainder" {
    var fake = Fake{};
    var base: Base = .init;
    const descriptor = setup(0x80, 6, 0x0200, 0, 255);
    base.on_setup_req(&fake.interface, &descriptor);
    try std.testing.expect(base.tx_slice.?.len > 0);
    const replacement = setup(0, 5, 12, 0, 0);
    base.on_setup_req(&fake.interface, &replacement);
    try std.testing.expect(base.tx_slice.?.len > 0);
}

test "pinned configuration descriptor byte audit" {
    var fake = Fake{};
    var base: Base = .init;
    const packet = setup(0x80, 6, 0x0200, 0, 255);
    base.on_setup_req(&fake.interface, &packet);
    for (0..3) |_| base.on_buffer(&fake.interface, .{ .num = .ep0, .dir = .in });
    try std.testing.expectEqualSlices(u8, &Wire.configuration, fake.stream[0..fake.stream_length]);
}

test "explicit configuration is a contiguous wire stream and driver pointers remain owned" {
    try std.testing.expectEqual(@as(usize, 137), Wire.configuration.len);
    var offset: usize = 0;
    while (offset < Wire.configuration.len) : (offset += Wire.configuration[offset]) {
        try std.testing.expect(Wire.configuration[offset] >= 7);
        try std.testing.expect(offset + Wire.configuration[offset] <= Wire.configuration.len);
    }
    try std.testing.expectEqual(Wire.configuration.len, offset);
    var fake = Fake{};
    var base: Base = .init;
    var initializer: descriptors.configuration.Initializer(usb, config, args) = .{};
    initializer.configure(&base, &fake.interface, 1);
    const drivers = base.drivers().?;
    try std.testing.expect(drivers.keyboard.descriptor == &initializer.descriptors[0]);
    try std.testing.expect(drivers.rawhid.base.descriptor == &initializer.descriptors[3]);
    try std.testing.expectEqual(@as(usize, 32), drivers.rawhid.base.descriptor.ep_out.max_packet_size.native());
    initializer.configure(&base, &fake.interface, 0);
    try std.testing.expect(base.drivers() == null);
}

test "RawHID rejects every short interrupt report and always rearms" {
    var fake = Fake{};
    var descriptor: descriptors.RawHid.Descriptor = undefined;
    descriptor.ep_out = .interrupt(@fromBackingInt(1), 32, 1);
    descriptor.ep_in = .interrupt(@fromBackingInt(2), 32, 1);
    var driver: descriptors.RawHid = undefined;
    driver.init(&descriptor, &fake.interface);
    var packet: usb.types.SetupPacket = @bitCast(@as(u64, 0));
    packet.request_type.type = .class;
    packet.request = 0x09;
    packet.length = .from(32);
    try std.testing.expectEqual(usb.nak, driver.class_request(&packet));
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
    for (33..65) |len| {
        fake.length = @intCast(len);
        driver.on_rx(descriptor.ep_out.endpoint.num);
        try std.testing.expect(driver.receive_report() == null);
    }
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

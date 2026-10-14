// SPDX-License-Identifier: GPL-2.0
//! Adapted from zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
//! Runtime descriptor storage for the pinned MicroZig driver boundary.
const std = @import("std");
const wire = @import("usb_descriptor_bytes.zig");

pub fn Initializer(comptime usb: type, comptime config: usb.Config, comptime args: config.DriverArgs()) type {
    const drivers = @typeInfo(config.configurations[0].Drivers).@"struct";
    const Descriptors = blk: {
        var types: [drivers.field_names.len]type = undefined;
        for (drivers.field_types, &types) |Driver, *T| T.* = Driver.Descriptor;
        break :blk @Tuple(&types);
    };
    const bytes = blk: {
        @setEvalBranchQuota(20000);
        var alloc = usb.DescriptorAllocator.init(config.unique_endpoints);
        _ = alloc.string(config.vendor.str);
        _ = alloc.string(config.product.str);
        _ = alloc.string(config.serial);
        _ = alloc.string(config.configurations[0].name);
        var types: [drivers.field_names.len]type = undefined;
        for (drivers.field_types, &types) |Driver, *T| T.* = [wire.size(Driver.Descriptor)]u8;
        var result: @Tuple(&types) = undefined;
        for (drivers.field_names, drivers.field_types, 0..) |name, Driver, i| {
            const desc = Driver.Descriptor.create(&alloc, config.max_supported_packet_size, @field(args[0], name));
            result[i] = wire.encode(desc.descriptor);
        }
        break :blk result;
    };
    return struct {
        descriptors: Descriptors = undefined,
        observe: ?*const fn (u8, u8, u8, u16) void = null,

        pub fn configure(self: *@This(), base: anytype, device: *usb.DeviceInterface, number: u16) void {
            std.debug.assert(number <= 1);
            base.driver_data = null;
            base.cfg_num = number;
            if (number == 0) return;
            base.driver_data = @as(config.configurations[0].Drivers, undefined);
            inline for (drivers.field_names, drivers.field_types, 0..) |name, Driver, i| {
                const T = Driver.Descriptor;
                self.descriptors[i] = wire.decode(T, &bytes[i]);
                if (self.observe) |observe| observe(2, @intCast(i), 0, 0);
                const desc = &self.descriptors[i];
                inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |part_name, Part| {
                    if (comptime Part == usb.descriptor.Endpoint) {
                        const endpoint = &@field(desc, part_name);
                        if (endpoint.endpoint.dir == .out) {
                            if (self.observe) |observe| observe(3, @intCast(i), @bitCast(endpoint.endpoint), endpoint.max_packet_size.native());
                            device.ep_open(endpoint);
                        }
                    }
                }
                const driver = &@field(base.driver_data.?, name);
                if (self.observe) |observe| observe(4, @intCast(i), 0, 0);
                if (@hasField(@TypeOf(base.driver_alloc), name)) {
                    driver.init(desc, device, &@field(base.driver_alloc, name));
                } else driver.init(desc, device);
                inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |part_name, Part| {
                    if (comptime Part == usb.descriptor.Endpoint) {
                        const endpoint = &@field(desc, part_name);
                        if (endpoint.endpoint.dir == .in) {
                            if (self.observe) |observe| observe(5, @intCast(i), @bitCast(endpoint.endpoint), endpoint.max_packet_size.native());
                            device.ep_open(endpoint);
                        }
                    }
                }
            }
            if (self.observe) |observe| observe(6, 0, 0, number);
        }
    };
}

//! Explicit wire descriptors and persistent driver storage.
//! Adapted from the GPL-2.0 reference at 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
const std = @import("std");
const wire = @import("usb_descriptor_bytes.zig");
pub const Initializer = @import("usb_driver_init.zig").Initializer;

pub fn descriptors(comptime usb: type, comptime config: usb.Config, comptime args: config.DriverArgs()) type {
    return struct {
        const data = blk: {
            @setEvalBranchQuota(30000);
            const cfg = config.configurations[0];
            var alloc: usb.DescriptorAllocator = .init(config.unique_endpoints);
            _ = alloc.string(config.vendor.str);
            _ = alloc.string(config.product.str);
            _ = alloc.string(config.serial);
            const name = alloc.string(cfg.name);
            const fields = @typeInfo(cfg.Drivers).@"struct";
            var length = wire.size(usb.descriptor.Configuration);
            var hid_count = 0;
            var endpoint_count = 0;
            for (fields.field_types) |Driver| {
                length += wire.size(Driver.Descriptor);
                if (@hasField(Driver.Descriptor, "hid")) hid_count += 1;
                for (@typeInfo(Driver.Descriptor).@"struct".field_types) |Part|
                    if (Part == usb.descriptor.Endpoint) {
                        endpoint_count += 1;
                    };
            }
            var bytes: [length]u8 = undefined;
            var hid_bytes: [hid_count][9]u8 = undefined;
            var endpoint_addresses: [endpoint_count]u8 = undefined;
            var report_slices: [hid_count][]const u8 = undefined;
            var h = 0;
            var e = 0;
            var rawhid_interface: ?u8 = null;
            var reset_interface_number: ?u8 = null;
            var offset = wire.size(usb.descriptor.Configuration);
            for (fields.field_names, fields.field_types) |name_field, Driver| {
                const desc = Driver.Descriptor.create(&alloc, config.max_supported_packet_size, @field(args[0], name_field)).descriptor;
                if (std.mem.eql(u8, name_field, "rawhid")) rawhid_interface = desc.interface.interface_number;
                if (std.mem.eql(u8, name_field, "reset")) {
                    for (@typeInfo(Driver.Descriptor).@"struct".field_names, @typeInfo(Driver.Descriptor).@"struct".field_types) |part_name, Part| {
                        if (Part == usb.descriptor.Interface) reset_interface_number = @field(desc, part_name).interface_number;
                    }
                }
                wire.append(&bytes, &offset, desc);
                if (@hasField(Driver.Descriptor, "hid")) {
                    hid_bytes[h] = wire.encode(desc.hid);
                    report_slices[h] = Driver.report_descriptor;
                    h += 1;
                }
                for (@typeInfo(Driver.Descriptor).@"struct".field_names, @typeInfo(Driver.Descriptor).@"struct".field_types) |part_name, Part| {
                    if (Part == usb.descriptor.Endpoint) {
                        endpoint_addresses[e] = @bitCast(@field(desc, part_name).endpoint);
                        e += 1;
                    }
                }
            }
            var start: usize = 0;
            wire.append(&bytes, &start, @as(usb.descriptor.Configuration, .{
                .total_length = .from(length),
                .num_interfaces = alloc.next_itf_num,
                .configuration_value = 1,
                .configuration_s = name,
                .attributes = cfg.attributes,
                .max_current = .from_ma(cfg.max_current_ma),
            }));
            std.debug.assert(offset == length);
            const device_descriptor: usb.descriptor.Device = .{
                .bcd_usb = config.bcd_usb,
                .device_triple = config.device_triple,
                .max_packet_size0 = config.max_supported_packet_size,
                .vendor = .from(config.vendor.id),
                .product = .from(config.product.id),
                .bcd_device = config.bcd_device,
                .manufacturer_s = 1,
                .product_s = 2,
                .serial_s = 3,
                .num_configurations = 1,
            };
            const string_desc = alloc.string_descriptors(config.language);
            var string_slices: [string_desc.len][]const u8 = undefined;
            for (string_desc, &string_slices) |desc, *value| value.* = desc.data;
            break :blk .{ .configuration = bytes, .hid = hid_bytes, .device = wire.encode(device_descriptor), .strings = string_slices, .reports = report_slices, .endpoints = endpoint_addresses, .vendor_interface = rawhid_interface, .reset_interface = reset_interface_number };
        };
        pub const configuration = data.configuration;
        pub const hid = data.hid;
        pub const device = data.device;
        pub const strings = data.strings;
        pub const reports = data.reports;
        pub const endpoints = data.endpoints;
        pub const vendor_interface = data.vendor_interface;
        pub const reset_interface = data.reset_interface;
    };
}

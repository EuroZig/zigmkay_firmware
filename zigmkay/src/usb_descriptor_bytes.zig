// SPDX-License-Identifier: GPL-2.0
//! Adapted from zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
//! Compile-time USB wire bytes must not depend on aggregate constant layout.
const std = @import("std");

pub fn size(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .int => |info| (info.bits + 7) / 8,
        .@"enum" => |info| size(info.tag_type),
        .array => |info| info.len * size(info.child),
        .@"struct" => |info| if (info.layout == .@"packed") size(info.backing_integer.?) else blk: {
            var result: usize = 0;
            inline for (info.field_types) |Field| result += size(Field);
            break :blk result;
        },
        else => @compileError("Unsupported USB descriptor field " ++ @typeName(T)),
    };
}

pub fn encode(comptime value: anytype) [size(@TypeOf(value))]u8 {
    var result: [size(@TypeOf(value))]u8 = undefined;
    var offset: usize = 0;
    append(&result, &offset, value);
    std.debug.assert(offset == result.len);
    return result;
}

pub fn append(output: []u8, offset: *usize, comptime value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .int => {
            inline for (0..comptime size(T)) |i| output[offset.* + i] = @truncate(value >> (8 * i));
            offset.* += size(T);
        },
        .@"enum" => append(output, offset, @backingInt(value)),
        .array => inline for (value) |element| append(output, offset, element),
        .@"struct" => |info| {
            if (info.layout == .@"packed") {
                append(output, offset, @as(info.backing_integer.?, @bitCast(value)));
            } else inline for (info.field_names) |name| append(output, offset, @field(value, name));
        },
        else => @compileError("Unsupported USB descriptor field " ++ @typeName(T)),
    }
}

/// Materialize descriptor fields in runtime storage, never copy a nested
/// compiler-emitted aggregate constant into the driver's descriptor memory.
pub fn decode(comptime T: type, bytes: []const u8) T {
    std.debug.assert(bytes.len == comptime size(T));
    var offset: usize = 0;
    const result = read(T, bytes, &offset);
    std.debug.assert(offset == bytes.len);
    return result;
}

fn read(comptime T: type, bytes: []const u8, offset: *usize) T {
    return switch (@typeInfo(T)) {
        .int => blk: {
            const U = @Int(.unsigned, @bitSizeOf(T));
            var value: U = 0;
            inline for (0..comptime size(T)) |i| value |= @as(U, @truncate(bytes[offset.* + i])) << (8 * i);
            offset.* += comptime size(T);
            break :blk @bitCast(value);
        },
        .@"enum" => |info| @fromBackingInt(read(info.tag_type, bytes, offset)),
        .array => |info| blk: {
            var value: T = undefined;
            for (&value) |*element| element.* = read(info.child, bytes, offset);
            break :blk value;
        },
        .@"struct" => |info| blk: {
            if (info.layout == .@"packed") break :blk @bitCast(read(info.backing_integer.?, bytes, offset));
            var value: T = undefined;
            inline for (info.field_names, info.field_types) |name, Field| @field(value, name) = read(Field, bytes, offset);
            break :blk value;
        },
        else => @compileError("Unsupported USB descriptor field " ++ @typeName(T)),
    };
}

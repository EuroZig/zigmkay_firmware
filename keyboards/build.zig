const std = @import("std");
const microzig = @import("microzig");
const api = @import("build_api.zig");
pub const boards = @import("boards.zig");
pub const addKeyboardFirmware = api.addKeyboardFirmware;
const MicroBuild = microzig.MicroBuild(.{ .rp2xxx = true });

pub fn build(b: *std.Build) void {
    const selected = b.option([]const u8, "keyboard", "Firmware selector from boards.zig") orelse boards.entries[0].name;
    const board = boards.find(selected) orelse std.debug.panic("Unknown keyboard selector: {s}", .{selected});
    const keymap_path = b.option([]const u8, "keymap", "Explicit supplied keymap source path (selected board only)");
    const companion_enabled = b.option(bool, "companion", "Enable telemetry with the supplied keymap's canonical identity") orelse false;
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;
    const target = mb.ports.rp2xxx.boards.raspberrypi.pico.*;
    const sources: api.Sources = .{
        .keyboards = b.path("."),
        .processor = b.path("../zigmkay/src/root.zig"),
        .keycodes = b.path("../zkeycodes/root.zig"),
        .companion_enabled = companion_enabled,
    };
    const firmware = addKeyboardFirmware(b, mb, &target, optimize, "zigmkay_firmware", board, sources, if (keymap_path) |path| .{ .cwd_relative = path } else null);
    mb.install_firmware(firmware, .{});
    const uf2 = firmware.get_emitted_bin(.{ .uf2 = .{ .family_id = .RP2040 } });
    b.addNamedLazyPath("firmware_uf2", uf2);

    const tests = b.step("test", "Run host regressions and compile every default firmware");
    const pinned_usb = b.createModule(.{ .root_source_file = mb.core_dep.path("src/microzig.zig") });
    const descriptors = b.createModule(.{
        .root_source_file = b.path("../zigmkay/src/usb_descriptors.zig"),
        .imports = &.{.{ .name = "microzig", .module = pinned_usb }},
    });
    const descriptor_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/test_usb_descriptors.zig"),
        .target = b.graph.host,
        .imports = &.{.{ .name = "usb_descriptors", .module = descriptors }},
    }) });
    tests.dependOn(&b.addRunArtifact(descriptor_tests).step);
    const processor = b.createModule(.{ .root_source_file = sources.processor });
    const keycodes = b.createModule(.{ .root_source_file = sources.keycodes, .imports = &.{.{ .name = "zigmkay", .module = processor }} });
    const default_keymap = b.createModule(.{
        .root_source_file = b.path("my_keyboards/janbeelte/clackychan_colemak_keymap.zig"),
        .imports = &.{ .{ .name = "zigmkay", .module = processor }, .{ .name = "zkeycodes", .module = keycodes } },
    });
    const regression = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/test_clackychan_combos.zig"),
        .target = b.graph.host,
        .imports = &.{ .{ .name = "zigmkay", .module = processor }, .{ .name = "clackychan_keymap", .module = default_keymap } },
    }) });
    tests.dependOn(&b.addRunArtifact(regression).step);
    const validation = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("keymap_validation.zig"),
        .target = b.graph.host,
        .imports = &.{.{ .name = "zigmkay", .module = processor }},
    }) });
    tests.dependOn(&b.addRunArtifact(validation).step);
    const rejected_sources = b.addWriteFiles();
    const validator_module = validation.root_module;
    for ([_]struct { name: []const u8, body: []const u8, message: []const u8 }{
        .{ .name = "missing-companion-identity", .body = "comptime { _ = validator.companionIdentity(struct {}, true); }", .message = "Companion telemetry requires a supplied canonical keymap identity" },
        .{ .name = "wrong-width", .body = "const Fixture = struct { pub const keymap = [1][1]?core.KeyDef{.{null}}; }; comptime { _ = validator.validate(Fixture, 2, null); }", .message = "Keymap key count does not match board wiring" },
        .{ .name = "wrong-sides", .body = "const Fixture = struct { pub const keymap = [1][2]?core.KeyDef{.{null, null}}; pub const sides = [2]core.Side{.R, .L}; }; comptime { _ = validator.validate(Fixture, 2, &.{.L, .R}); }", .message = "Keymap sides differ from board side ownership" },
        .{ .name = "wrong-encoder-slots", .body = "const Fixture = struct { pub const encoder_actions = [1]core.EncoderAction{.{.tap=.{.media_key=.VolumeUp}}}; }; comptime { _ = validator.encoderActions(Fixture, [2]core.EncoderAction{.{.tap=.{.media_key=.VolumeUp}}, .{.tap=.{.media_key=.VolumeDown}}}); }", .message = "Encoder action slot count does not match board wiring" },
    }) |fixture| {
        const source = rejected_sources.add(b.fmt("{s}.zig", .{fixture.name}), b.fmt("const core = @import(\"zigmkay\").core; const validator = @import(\"validator\");\n{s}\n", .{fixture.body}));
        const rejected = b.addObject(.{ .name = fixture.name, .root_module = b.createModule(.{
            .root_source_file = source,
            .target = b.graph.host,
            .imports = &.{ .{ .name = "zigmkay", .module = processor }, .{ .name = "validator", .module = validator_module } },
        }) });
        rejected.expect_errors = .{ .contains = fixture.message };
        tests.dependOn(&rejected.step);
    }
    const inventory = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("boards.zig"), .target = b.graph.host }) });
    tests.dependOn(&b.addRunArtifact(inventory).step);
    const processing_contract = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("processing_descriptors.zig"),
        .target = b.graph.host,
        .imports = &.{.{ .name = "zigmkay", .module = processor }},
    }) });
    tests.dependOn(&b.addRunArtifact(processing_contract).step);
    var default_sources = sources;
    default_sources.companion_enabled = false;
    for (boards.entries) |entry| {
        const item = addKeyboardFirmware(b, mb, &target, optimize, entry.name, entry, default_sources, null);
        tests.dependOn(&item.exe.step);
    }

    const fixtures = b.addWriteFiles();
    var observed_sources = sources;
    observed_sources.companion_enabled = true;
    for ([_]struct { board: []const u8, keys: usize, encoders: usize }{
        .{ .board = "lk7", .keys = 34, .encoders = 0 },
        .{ .board = "dasbob", .keys = 36, .encoders = 0 },
        .{ .board = "encoder_demo", .keys = 1, .encoders = 2 },
    }) |fixture| {
        const source = fixtures.add(b.fmt("observed-{s}.zig", .{fixture.board}), b.fmt(
            \\const core = @import("zigmkay").core;
            \\pub const keymap = [1][{d}]?core.KeyDef{{ @splat(null) }};
            \\pub const combos = [_]core.Combo2Def{{}};
            \\pub const custom_functions: core.CustomFunctions = .{{ .on_event = null }};
            \\pub const encoder_actions: [{d}]core.EncoderAction = @splat(.{{ .tap = .{{ .media_key = .VolumeDown }} }});
            \\pub fn identity(comptime protocol: type) protocol.Identity {{
            \\    return protocol.computeIdentity(.{{ .board_id = .{{'f','i','x','t','u','r','e',0}}, .profile_id = .{{'o','b','s','e','r','v','e',0}},
            \\        .dimensions = .{{ .key_count = {d}, .layer_count = 1 }}, .keys = &keymap[0],
            \\        .sides = &@as([{d}]core.Side, @splat(.X)), .combos = &combos,
            \\        .encoders = &encoder_actions, .callbacks = &.{{}} }}) catch unreachable;
            \\}}
            \\
        , .{ fixture.keys, fixture.encoders, fixture.keys, fixture.keys }));
        const item = addKeyboardFirmware(b, mb, &target, optimize, b.fmt("observed-{s}", .{fixture.board}), boards.find(fixture.board).?, observed_sources, source);
        tests.dependOn(&item.exe.step);
    }

    // Tool preparation is explicit; no default/test graph resolves flashing tools.
    if (b.option(bool, "flash-tools", "Prepare optional picotool flash step") orelse false) {
        const dep = b.dependency("zigmkay", .{ .@"flash-tools" = true });
        const flash = @import("zigmkay").addPicotoolFlash(b, dep, uf2);
        b.step("flash", "Flash the selected firmware (explicit device operation)").dependOn(&flash.step);
    }
}

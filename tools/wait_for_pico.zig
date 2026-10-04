const std = @import("std");

const poll_interval: std.Io.Duration = .fromMilliseconds(200);

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    std.debug.print("Waiting for an RP-series device in BOOTSEL mode...\n", .{});

    while (true) {
        var child = std.process.spawn(io, .{
            .argv = &.{ "picotool", "info" },
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch |err| switch (err) {
            error.FileNotFound => std.process.fatal(
                "unable to run picotool; make sure it is installed and in PATH",
                .{},
            ),
            else => return err,
        };

        const term = try child.wait(io);
        if (term.success()) break;

        try std.Io.sleep(io, poll_interval, .awake);
    }

    std.debug.print("BOOTSEL device found; flashing...\n", .{});
}

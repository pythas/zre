const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

const GameMode = @import("modes/game_mode.zig").GameMode;

pub fn main() !void {
    try zglfw.init();
    defer zglfw.terminate();

    zglfw.windowHintString(.x11_class_name, "zdse");
    zglfw.windowHintString(.x11_instance_name, "zdse");

    const window = try zglfw.Window.create(1200, 700, "zre", null);
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const gctx = try zgpu.GraphicsContext.create(
        gpa,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{},
    );
    defer gctx.destroy(gpa);

    var game = try GameMode.init(gpa, gctx, .{
        .map_source = .{ .path = "assets/maps/map01.json" },
    });
    defer game.deinit();

    var last_time: f64 = zglfw.getTime();

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();

        const now = zglfw.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;

        try game.update(dt);

        const swapchain_texv = gctx.swapchain.getCurrentTextureView();
        defer swapchain_texv.release();

        const commands = commands: {
            const encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();

            // World pass
            {
                const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texv, null, null, null);
                defer zgpu.endReleasePass(pass);

                game.render(pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();

        gctx.submit(&.{commands});
        _ = gctx.present();
    }
}

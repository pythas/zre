const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

const Renderer = @import("renderer.zig").Renderer;
const GameMode = @import("modes/game_mode.zig").GameMode;

pub fn main() !void {
    try initWindow();
    defer zglfw.terminate();

    const window = try createMainWindow();
    defer window.destroy();

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const renderer = try Renderer.init(gpa, window);
    defer renderer.deinit(gpa);
    // zstbi.init(allocator);
    // defer zstbi.deinit();

    var game = try GameMode.init(gpa, renderer.gctx, .{
        .map_source = .{ .path = "assets/maps/map01.json" },
        .bind_group_layout = renderer.bind_group_layout,
        .uniforms_buffer = renderer.uniforms_buffer,
        .pipeline = renderer.pipeline,
        .window = window,
    });
    defer game.deinit();

    try runGameLoop(window, &game, renderer.gctx);
}

fn initWindow() !void {
    try zglfw.init();
    zglfw.windowHintString(.x11_class_name, "zdse");
    zglfw.windowHintString(.x11_instance_name, "zdse");
}

fn createMainWindow() !*zglfw.Window {
    const window = try zglfw.Window.create(1200, 700, "zre", null);
    window.setSizeLimits(400, 400, -1, -1);
    return window;
}

fn runGameLoop(window: *zglfw.Window, game: *GameMode, gctx: *zgpu.GraphicsContext) !void {
    var last_time: f64 = zglfw.getTime();

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();

        const now = zglfw.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;

        try game.update(dt);

        try renderFrame(gctx, game);
    }
}

fn renderFrame(gctx: *zgpu.GraphicsContext, game: *const GameMode) !void {
    const swapchain_texv = gctx.swapchain.getCurrentTextureView();
    defer swapchain_texv.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

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

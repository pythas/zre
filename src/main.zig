const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

const Renderer = @import("renderer.zig").Renderer;
const GameMode = @import("modes/game_mode.zig").GameMode;
const EditorMode = @import("modes/editor_mode.zig").EditorMode;
const Map = @import("map.zig").Map;

pub const ModeTag = enum {
    game,
    editor,
};

pub const Mode = union(ModeTag) {
    const Self = @This();

    game: GameMode,
    editor: EditorMode,

    pub fn initGame(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        config: GameMode.Config,
    ) !Self {
        return .{
            .game = try GameMode.init(allocator, gctx, config),
        };
    }

    pub fn initEditor(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        config: EditorMode.Config,
    ) !Self {
        return .{
            .editor = try EditorMode.init(allocator, gctx, config),
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .game => |*game| game.deinit(),
            .editor => |*editor| editor.deinit(),
        }
    }

    pub fn update(self: *Self, dt: f32) !void {
        switch (self.*) {
            .game => |*game| try game.update(dt),
            .editor => |*editor| try editor.update(dt),
        }
    }

    pub fn render(self: *Self, pass: zgpu.wgpu.RenderPassEncoder) void {
        switch (self.*) {
            .game => |*game| game.render(pass),
            .editor => |*editor| editor.render(pass),
        }
    }
};

const KeyLatch = struct {
    prev_f1: bool = false,

    pub fn pressedF1(self: *KeyLatch, window: *zglfw.Window) bool {
        const now = window.getKey(.F1) == .press;
        defer self.prev_f1 = now;
        return (now and !self.prev_f1);
    }
};

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

    try runGameLoop(gpa, window, renderer);
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

fn runGameLoop(
    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    renderer: Renderer,
) !void {
    var last_time: f64 = zglfw.getTime();

    var map = try Map.initFromPath(allocator, "assets/maps/map02.json");

    var mode = try Mode.initGame(allocator, renderer.gctx, .{
        .map = &map,
        .bind_group_layout = renderer.bind_group_layout,
        .uniforms_buffer = renderer.uniforms_buffer,
        .pipeline = renderer.pipeline,
        .window = window,
    });
    defer mode.deinit();

    var latch = KeyLatch{};

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();

        const now = zglfw.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;

        if (latch.pressedF1(window)) {
            const new_mode: Mode = switch (mode) {
                .game => try Mode.initEditor(allocator, renderer.gctx, .{
                    .map = &map,
                    .bind_group_layout = renderer.bind_group_layout,
                    .uniforms_buffer = renderer.uniforms_buffer,
                    .window = window,
                }),
                .editor => try Mode.initGame(allocator, renderer.gctx, .{
                    .map = &map,
                    .bind_group_layout = renderer.bind_group_layout,
                    .uniforms_buffer = renderer.uniforms_buffer,
                    .pipeline = renderer.pipeline,
                    .window = window,
                }),
            };
            mode.deinit();
            mode = new_mode;
        }

        try mode.update(dt);
        try renderFrame(renderer.gctx, &mode);
    }
}

fn renderFrame(gctx: *zgpu.GraphicsContext, mode: *Mode) !void {
    const swapchain_texv = gctx.swapchain.getCurrentTextureView();
    defer swapchain_texv.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        {
            const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texv, null, null, null);
            defer zgpu.endReleasePass(pass);

            mode.render(pass);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});
    _ = gctx.present();
}

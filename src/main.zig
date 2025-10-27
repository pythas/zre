const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

const GameMode = @import("modes/game_mode.zig").GameMode;
const EditorMode = @import("modes/editor_mode.zig").EditorMode;
const Map = @import("map.zig").Map;
const MapResult = @import("map.zig").MapResult;

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
        window: *zglfw.Window,
        map_result: *MapResult,
    ) !Self {
        return .{
            .game = try GameMode.init(
                allocator,
                gctx,
                window,
                map_result,
            ),
        };
    }

    pub fn initEditor(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
    ) !Self {
        return .{
            .editor = try EditorMode.init(
                allocator,
                gctx,
                window,
            ),
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

    pub fn render(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        dt: f32,
        t: f32,
    ) !void {
        switch (self.*) {
            .game => |*game| try game.render(pass, dt, t),
            .editor => |*editor| try editor.render(pass),
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

    // var renderer = try Renderer.init(gpa, window);
    // defer renderer.deinit(gpa);

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

    try runGameLoop(gpa, window, gctx);
}

fn initWindow() !void {
    try zglfw.init();
    zglfw.windowHintString(.x11_class_name, "zre");
    zglfw.windowHintString(.x11_instance_name, "zre");
}

fn createMainWindow() !*zglfw.Window {
    const window = try zglfw.Window.create(800, 600, "zre", null);
    window.setSizeLimits(400, 400, -1, -1);
    return window;
}

fn runGameLoop(
    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    gctx: *zgpu.GraphicsContext,
) !void {
    var last_time: f64 = zglfw.getTime();

    var map_result = try Map.initFromPath(allocator, "assets/maps/map02.json");

    var mode = try Mode.initGame(
        allocator,
        gctx,
        window,
        &map_result,
    );
    defer mode.deinit();

    var latch = KeyLatch{};
    var fps = FpsCounter{};
    const st = zglfw.getTime();

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();

        const now = zglfw.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;

        const t: f32 = @floatCast(now - st);

        fps.update(dt);

        if (fps.shouldRefreshTitle()) {
            const fps_avg = @as(f64, @floatFromInt(fps.acc_frames)) / fps.acc_time;
            std.debug.print("\rFPS: {d:5.1} | frametime: {d:6.2} ms/n", .{ fps_avg, fps.ema_ms });
            fps.acc_time = 0.0;
            fps.acc_frames = 0;
        }

        if (latch.pressedF1(window)) {
            mode.deinit();
            const new_mode: Mode = switch (mode) {
                .game => try Mode.initEditor(
                    allocator,
                    gctx,
                    window,
                ),
                .editor => blk: {
                    map_result = try Map.initFromPath(allocator, "assets/maps/map02.json");
                    break :blk try Mode.initGame(
                        allocator,
                        gctx,
                        window,
                        &map_result,
                    );
                },
            };
            mode = new_mode;
        }

        try mode.update(dt);
        try renderFrame(gctx, &mode, dt, t);
    }
}

fn renderFrame(
    gctx: *zgpu.GraphicsContext,
    mode: *Mode,
    dt: f32,
    t: f32,
) !void {
    const swapchain_texv = gctx.swapchain.getCurrentTextureView();
    defer swapchain_texv.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        {
            const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texv, null, null, null);
            defer zgpu.endReleasePass(pass);

            try mode.render(pass, dt, t);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});
    _ = gctx.present();
}

const FpsCounter = struct {
    ema_ms: f64 = 16.0,
    alpha: f64 = 0.10,
    acc_time: f64 = 0.0,
    acc_frames: u32 = 0,

    pub fn update(self: *FpsCounter, dt: f64) void {
        const ms = dt * 1000.0;
        self.ema_ms = self.alpha * ms + (1.0 - self.alpha) * self.ema_ms;
        self.acc_time += dt;
        self.acc_frames += 1;
    }

    pub fn shouldRefreshTitle(self: *FpsCounter) bool {
        return self.acc_time >= 0.5;
    }
};

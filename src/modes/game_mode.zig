const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const StreamingTexture = @import("../streaming_texture.zig").StreamingTexture;
const World = @import("../world.zig").World;
const Map = @import("../map.zig").Map;
const MapResult = @import("../map.zig").MapResult;
const MapSource = @import("../world.zig").MapSource;
const KeyboardState = @import("../world.zig").KeyboardState;
const Renderer = @import("../renderer.zig").Renderer;

pub const GameMode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    renderer: Renderer,
    keyboard_state: KeyboardState,
    world: World,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        map_result: *MapResult,
    ) !Self {
        const world = try World.init(allocator, map_result);
        const renderer = try Renderer.init(allocator, gctx, window, &world.map);

        const keyboard_state = KeyboardState.init(window);

        return .{
            .allocator = allocator,
            .world = world,
            .window = window,
            .renderer = renderer,
            .keyboard_state = keyboard_state,
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
        self.renderer.deinit(self.allocator);
    }

    pub fn update(self: *Self, dt: f32) !void {
        self.keyboard_state.beginFrame();
        self.world.update(dt, &self.keyboard_state);
    }

    pub fn render(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        dt: f32,
        t: f32,
    ) !void {
        const renderer = self.renderer;
        const gctx = renderer.gctx;

        try renderer.writeTextures(&self.world);
        renderer.writeBuffers(&self.world, dt, t);

        const pipeline = gctx.lookupResource(renderer.pipeline).?;
        pass.setPipeline(pipeline);

        const bind_group = gctx.lookupResource(self.renderer.bind_group).?;
        pass.setBindGroup(0, bind_group, null);

        pass.draw(3, 1, 0, 0);

        self.world.map.is_dirty = false;
    }
};

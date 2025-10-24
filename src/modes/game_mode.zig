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

    world: World,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        map_result: *MapResult,
    ) !Self {
        const world = try World.init(allocator, map_result);
        const renderer = try Renderer.init(allocator, gctx, window, &map_result.map);

        return .{
            .allocator = allocator,
            .world = world,
            .window = window,
            .renderer = renderer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
        self.renderer.deinit(self.allocator);
    }

    pub fn update(self: *Self, dt: f32) !void {
        const keyboard_state = KeyboardState{
            .window = self.window,
        };

        self.world.update(dt, &keyboard_state);
    }

    pub fn render(self: Self, pass: zgpu.wgpu.RenderPassEncoder) !void {
        const renderer = self.renderer;
        const gctx = renderer.gctx;

        renderer.writeBuffers(&self.world);

        const pipeline = gctx.lookupResource(renderer.pipeline).?;
        pass.setPipeline(pipeline);

        const bind_group = gctx.lookupResource(self.renderer.bind_group).?;
        pass.setBindGroup(0, bind_group, null);

        pass.draw(3, 1, 0, 0);
    }
};

const std = @import("std");
const zgpu = @import("zgpu");

const StreamingTexture = @import("../streaming_texture.zig").StreamingTexture;
const World = @import("../world.zig").World;
const MapSource = @import("../world.zig").MapSource;

pub const GameMode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    screen: StreamingTexture,
    world: World,

    pub const Config = struct {
        map_source: MapSource,
    };

    pub fn init(allocator: std.mem.Allocator, gctx: *zgpu.GraphicsContext, config: Config) !Self {
        const width = gctx.swapchain_descriptor.width;
        const height = gctx.swapchain_descriptor.height;
        const screen = try StreamingTexture.init(allocator, gctx, width, height);
        const world = try World.init(allocator, config.map_source);

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .screen = screen,
            .world = world,
        };
    }

    pub fn deinit(self: Self) void {
        self.world.deinit();
    }

    pub fn update(self: Self, dt: f32) !void {
        self.world.update(dt);

        self.world.rasterize(&self.screen.texture_buffer);
    }

    pub fn render(self: Self, pass: zgpu.wgpu.RenderPassEncoder) void {
        pass.setPipeline(self.pipe);
        pass.setBindGroup(0, self.bg, null);
        pass.draw(3, 1, 0, 0);
    }
};

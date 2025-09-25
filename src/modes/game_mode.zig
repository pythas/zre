const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const StreamingTexture = @import("../streaming_texture.zig").StreamingTexture;
const World = @import("../world.zig").World;
const MapSource = @import("../world.zig").MapSource;
const KeyboardState = @import("../world.zig").KeyboardState;

pub const GameMode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    screen: StreamingTexture,
    world: World,
    pipeline: zgpu.RenderPipelineHandle,
    window: *zglfw.Window,

    pub const Config = struct {
        map_source: MapSource,
        bind_group_layout: zgpu.BindGroupLayoutHandle,
        uniforms_buffer: zgpu.BufferHandle,
        pipeline: zgpu.RenderPipelineHandle,
        window: *zglfw.Window,
    };

    pub fn init(allocator: std.mem.Allocator, gctx: *zgpu.GraphicsContext, config: Config) !Self {
        const width = gctx.swapchain_descriptor.width;
        const height = gctx.swapchain_descriptor.height;
        const screen = try StreamingTexture.init(allocator, gctx, config.bind_group_layout, config.uniforms_buffer, width, height);
        const world = try World.init(allocator, config.map_source);

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .screen = screen,
            .world = world,
            .pipeline = config.pipeline,
            .window = config.window,
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
        self.screen.deinit();
    }

    pub fn update(self: *Self, dt: f32) !void {
        const keyboard_state = KeyboardState{
            .window = self.window,
        };

        self.world.update(dt, &keyboard_state);
        self.world.rasterize(&self.screen.texture_buffer);
        self.screen.upload();
    }

    pub fn render(self: Self, pass: zgpu.wgpu.RenderPassEncoder) void {
        // Set the pipeline
        const pipeline = self.gctx.lookupResource(self.pipeline).?;
        pass.setPipeline(pipeline);

        // Use the bind group from the streaming texture
        const bind_group = self.gctx.lookupResource(self.screen.bind_group).?;
        pass.setBindGroup(0, bind_group, null);

        // Draw a quad covering the screen
        pass.draw(6, 1, 0, 0);
    }
};

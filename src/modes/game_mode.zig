const std = @import("std");
const zgpu = @import("zgpu");

const World = @import("../world.zig").World;
const MapSource = @import("../world.zig").MapSource;

pub const GameMode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    world: World,

    pub const Config = struct {
        map_source: MapSource,
    };

    pub fn init(allocator: std.mem.Allocator, gctx: *zgpu.GraphicsContext, config: Config) !Self {
        const world = try World.init(allocator, config.map_source);

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .world = world,
        };
    }

    pub fn deinit(self: Self) void {
        self.world.deinit();
    }

    pub fn update(_: Self, _: f32) !void {}

    pub fn render(_: Self, _: zgpu.wgpu.RenderPassEncoder) void {}
};

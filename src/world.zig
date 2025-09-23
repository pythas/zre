const std = @import("std");
const zgpu = @import("zgpu");

const TextureBuffer = @import("texture_buffer.zig").TextureBuffer;

pub const MapSource = union(enum) {
    path: []const u8,
    json: []const u8,
};

const Map = @import("map.zig").Map;
const Player = @import("player.zig").Player;

pub const World = struct {
    const Self = @This();

    map: Map,
    player: Player,

    pub fn init(allocator: std.mem.Allocator, map_source: MapSource) !Self {
        const map = switch (map_source) {
            .path => |path| try Map.initFromPath(allocator, path),
            .json => |path| try Map.initFromJson(allocator, path),
        };

        const player = try Player.init(allocator);

        return .{
            .map = map,
            .player = player,
        };
    }

    pub fn deinit(self: Self) void {
        self.map.deinit();
    }

    pub fn update(self: Self, dt: f32) void {
        _ = self;
        _ = dt;
    }

    pub fn rasterize(self: Self, texture_buffer: *TextureBuffer) void {
        _ = self;

        texture_buffer.clear();
    }
};

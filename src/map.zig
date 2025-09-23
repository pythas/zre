const std = @import("std");

pub const Tile = enum(u8) {
    Empty = 0,
    Wall = 1,
};

const JsonMap = struct {
    width: i32,
    height: i32,
    tiles: [][]i32,
};

pub const Map = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    data: []Tile,

    pub fn initEmpty(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn initFromPath(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const reader = file.reader();

        const file_size = try file.getEndPos();
        const json = try allocator.alloc(u8, file_size);
        defer allocator.free(json);

        _ = try reader.readAll(json);

        return Self.initFromJson(allocator, json);
    }

    pub fn initFromJson(allocator: std.mem.Allocator, json: []const u8) !Self {
        const parsed = try std.json.parseFromSlice(JsonMap, allocator, json, .{});
        defer parsed.deinit();

        const width: usize = @intCast(parsed.value.width);
        const height: usize = @intCast(parsed.value.height);
        const data = try allocator.alloc(Tile, width * height);

        for (parsed.value.tiles, 0..) |tiles, row| {
            for (tiles, 0..) |tile, col| {
                data[row * width + col] = switch (tile) {
                    0 => Tile.Empty,
                    1 => Tile.Wall,
                    else => Tile.Empty,
                };
            }
        }

        return .{
            .width = width,
            .height = height,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data);
    }
};

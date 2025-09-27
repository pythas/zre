const std = @import("std");
const zstbi = @import("zstbi");

const Texture = @import("texture.zig").Texture;
const PointLight = @import("point_light.zig").PointLight;
const Vec3 = @import("vec3.zig").Vec3;

pub const Tile = struct {
    const Self = @This();

    pub const Kind = enum(u8) {
        Empty = 0,
        Wall = 1,
        AnotherWall = 2,
    };

    kind: Kind,
    texture: ?u8,

    pub fn init(kind: Kind, texture: ?u8) Self {
        return .{
            .kind = kind,
            .texture = texture,
        };
    }

    pub fn initEmpty() Self {
        return .{
            .kind = .Empty,
            .texture = null,
        };
    }
};

const JsonTexture = struct {
    path: []const u8,
    width: i32,
    height: i32,
};

const JsonLightning = struct {
    ambient: [3]f32,
    point_lights: []JsonPointLight,
};

const JsonQuadraticAttenuation = struct {
    linear: f32,
    quadratic: f32,
};

const JsonPointLight = struct {
    position: [3]f32,
    color: [3]f32,
    intensity: f32,
    quadratic_attenuation: ?JsonQuadraticAttenuation,
    casts_shadows: bool,
    enabled: bool,
};

// const JsonDirectionalLight = struct {};

const JsonCeiling = struct {
    texture: i32,
};

const JsonFloor = struct {
    texture: i32,
};

const JsonTile = struct {
    kind: i32,
    texture: ?i32 = null,
};

const JsonMap = struct {
    width: i32,
    height: i32,
    textures: []JsonTexture,
    lightning: JsonLightning,
    ceiling: JsonCeiling,
    floor: JsonFloor,
    tiles: [][]JsonTile,
};

pub const Lightning = struct {
    const Self = @This();

    ambient: [3]f32,
    point_lights: std.ArrayList(PointLight),

    pub fn init(ambient: [3]f32, point_lights: std.ArrayList(PointLight)) Self {
        return .{
            .ambient = ambient,
            .point_lights = point_lights,
        };
    }
};

pub const Map = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    data: []Tile,
    ceiling: usize,
    floor: usize,
    textures: std.ArrayList(Texture),
    lightning: Lightning,

    pub fn initEmpty(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .textures = std.ArrayList([]u8).init(allocator),
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
                const kind = switch (tile.kind) {
                    0 => Tile.Kind.Empty,
                    1 => Tile.Kind.Wall,
                    else => Tile.Kind.Empty,
                };

                data[row * width + col] = Tile.init(kind, if (tile.texture) |texture| @intCast(texture) else null);
            }
        }

        var textures = std.ArrayList(Texture).init(allocator);

        for (parsed.value.textures) |texture| {
            try textures.append(try Texture.init(allocator, texture.path));
        }

        const ambient = parsed.value.lightning.ambient;

        var point_lights = std.ArrayList(PointLight).init(allocator);

        for (parsed.value.lightning.point_lights) |light| {
            try lights.append(
                Light.init(
                    kind,
                    Vec3.init(light.position[0], light.position[1], light.position[2]),
                    light.color,
                ),
            );
        }

        const lightning = Lightning.init(ambient, point_lights);

        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .data = data,
            .ceiling = @intCast(parsed.value.ceiling.texture),
            .floor = @intCast(parsed.value.floor.texture),
            .textures = textures,
            .lightning = lightning,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data);
    }

    pub fn getTile(self: Self, x: i32, y: i32) Tile {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) {
            return Tile.initEmpty();
        }

        return self.data[@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))];
    }

    pub fn getTileTexture(self: Self, x: i32, y: i32) !Texture {
        const tile = self.getTile(x, y);

        std.debug.assert(tile < self.textures.items.len);

        return self.textures[tile];
    }
};

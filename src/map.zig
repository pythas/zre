const std = @import("std");
const zstbi = @import("zstbi");

const Texture = @import("texture.zig").Texture;
const Light = @import("light.zig").Light;
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

const JsonLight = struct {
    type: []const u8,
    position: ?[3]f32 = null,
    direction: ?[3]f32 = null,
    color: [3]f32,
    intensity: f32,
    attenuation: ?struct {
        type: []const u8,
        linear: ?f32 = null,
        quadratic: ?f32 = null,
        radius: ?f32 = null,
    } = null,
    casts_shadows: bool,
    enabled: bool,
};

const JsonLightning = struct {
    ambient: [3]f32,
    lights: []JsonLight,
};

const JsonQuadraticAttenuation = struct {
    linear: f32,
    quadratic: f32,
};

const JsonRadialAttenuation = struct {
    radius: f32,
};

const JsonAttenuation = union(enum) {
    quadratic: JsonQuadraticAttenuation,
    radial: JsonRadialAttenuation,
};

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
    render: ?struct {
        ambient_plane: ?f32 = null,
        diffuse_plane: ?f32 = null,
        diffuse_wall: ?f32 = null,
        player_height: ?f32 = null,
        light_height_bias: ?f32 = null,
        fog: ?struct {
            enabled: bool = false,
            color: [3]f32 = .{ 0.0, 0.0, 0.0 },
            density: f32 = 0.04,
        } = null,
    } = null,
};

pub const Lightning = struct {
    const Self = @This();

    ambient: [3]f32,
    lights: std.ArrayList(Light),

    pub fn init(ambient: [3]f32, lights: std.ArrayList(Light)) Self {
        return .{
            .ambient = ambient,
            .lights = lights,
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
    render_settings: RenderSettings,

    pub const RenderSettings = struct {
        const Self = @This();
        ambient_plane: f32 = 0.22,
        diffuse_plane: f32 = 0.88,
        diffuse_wall: f32 = 0.90,
        player_height: f32 = 0.9,
        light_height_bias: f32 = 0.5,
        fog: FogSettings = .{},
    };

    pub const FogSettings = struct { enabled: bool = false, color: [3]f32 = .{ 0.0, 0.0, 0.0 }, density: f32 = 0.04 };
    pub const Emissive = struct { index: u32, intensity: f32 };
    pub const SpecularSettings = struct { enabled: bool = false, power: f32 = 16.0, strength: f32 = 0.3 };

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

        var lights = std.ArrayList(Light).init(allocator);

        for (parsed.value.lightning.lights) |light| {
            if (std.mem.eql(u8, light.type, "point")) {
                var attenuation: Light.Attenuation = .{
                    .quadratic = .{
                        .linear = 0.35,
                        .quadratic = 0.20,
                    },
                };

                if (light.attenuation) |att| {
                    if (std.mem.eql(u8, att.type, "quadratic")) {
                        attenuation = .{
                            .quadratic = .{
                                .linear = att.linear orelse 0.35,
                                .quadratic = att.quadratic orelse 0.20,
                            },
                        };
                    } else if (std.mem.eql(u8, att.type, "radial")) {
                        attenuation = .{
                            .radial = .{
                                .radius = att.radius orelse 1.0,
                            },
                        };
                    }
                }

                const pl = Light.PointLight.init(
                    Vec3.init(light.position.?[0], light.position.?[1], light.position.?[2]),
                    light.color,
                    light.intensity,
                    attenuation,
                    light.casts_shadows,
                    light.enabled,
                );

                try lights.append(.{ .point = pl });
            } else if (std.mem.eql(u8, light.type, "directional")) {
                const dl = Light.DirectionalLight.init(
                    Vec3.init(light.direction.?[0], light.direction.?[1], light.direction.?[2]),
                    light.color,
                    light.intensity,
                    light.casts_shadows,
                    light.enabled,
                );

                try lights.append(.{ .directional = dl });
            }
        }

        const lightning = Lightning.init(ambient, lights);

        var render_settings: RenderSettings = .{};
        if (parsed.value.render) |r| {
            if (r.ambient_plane) |v| render_settings.ambient_plane = v;
            if (r.diffuse_plane) |v| render_settings.diffuse_plane = v;
            if (r.diffuse_wall) |v| render_settings.diffuse_wall = v;
            if (r.player_height) |v| render_settings.player_height = v;
            if (r.light_height_bias) |v| render_settings.light_height_bias = v;
            if (r.fog) |f| {
                render_settings.fog = .{ .enabled = f.enabled, .color = f.color, .density = f.density };
            }
        }

        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .data = data,
            .ceiling = @intCast(parsed.value.ceiling.texture),
            .floor = @intCast(parsed.value.floor.texture),
            .textures = textures,
            .lightning = lightning,
            .render_settings = render_settings,
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

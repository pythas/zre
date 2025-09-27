const std = @import("std");
const zgpu = @import("zgpu");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

pub const MapSource = union(enum) {
    path: []const u8,
    json: []const u8,
};

pub const KeyboardState = struct {
    const Self = @This();

    window: *zglfw.Window,

    pub const Key = enum {
        w,
        a,
        s,
        d,
        q,
        e,
        up,
        down,
        left,
        right,
    };

    pub fn isKeyPressed(self: Self, key: Key) bool {
        return switch (key) {
            .w => self.window.getKey(.w) == .press,
            .a => self.window.getKey(.a) == .press,
            .s => self.window.getKey(.s) == .press,
            .d => self.window.getKey(.d) == .press,
            .q => self.window.getKey(.q) == .press,
            .e => self.window.getKey(.e) == .press,
            .up => self.window.getKey(.up) == .press,
            .down => self.window.getKey(.down) == .press,
            .left => self.window.getKey(.left) == .press,
            .right => self.window.getKey(.right) == .press,
        };
    }
};

const TextureBuffer = @import("texture_buffer.zig").TextureBuffer;
const Vec2 = @import("vec2.zig").Vec2;
const Map = @import("map.zig").Map;
const Player = @import("player.zig").Player;
const Camera = @import("camera.zig").Camera;
const Tile = @import("map.zig").Tile;
const Texture = @import("texture.zig").Texture;

// TODO: Move these helper functions to a utility file
fn f32ToI32(value: f32) i32 {
    return @intFromFloat(@min(value, @as(f32, @floatFromInt(math.maxInt(i32)))));
}

fn uToI32(value: anytype) i32 {
    return @intCast(value);
}

const stride = 64 * 4;

fn sample(texture: []u8, x: usize, y: usize) [4]u8 {
    const i = y * stride + x * 4;

    return .{
        texture[i],
        texture[i + 1],
        texture[i + 2],
        texture[i + 3],
    };
}

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    map: Map,
    player: Player,
    camera: Camera,
    light_dir: Vec2,

    pub fn init(allocator: std.mem.Allocator, map_source: MapSource) !Self {
        var map = switch (map_source) {
            .path => |path| try Map.initFromPath(allocator, path),
            .json => |path| try Map.initFromJson(allocator, path),
        };

        try map.textures.append(try Texture.init(allocator, "assets/textures/STEEL_1C.PNG"));
        try map.textures.append(try Texture.init(allocator, "assets/textures/STEEL_1A.PNG"));
        try map.textures.append(try Texture.init(allocator, "assets/textures/BRICK_3A.PNG"));

        const player = try Player.init(
            Vec2.init(7.5, 7.5),
            Vec2.init(-1.0, 0.0),
        );

        const camera = try Camera.init(
            Vec2.init(0.0, 0.66),
        );

        return .{
            .allocator = allocator,
            .map = map,
            .player = player,
            .camera = camera,
            .light_dir = Vec2.init(0.2, 0.6).normalize(),
        };
    }

    pub fn deinit(self: Self) void {
        self.map.deinit();
    }

    pub fn update(self: *Self, dt: f32, keyboard_state: *const KeyboardState) void {
        if (keyboard_state.isKeyPressed(.w) or keyboard_state.isKeyPressed(.up)) {
            self.movePlayerForward(dt);
        }

        if (keyboard_state.isKeyPressed(.s) or keyboard_state.isKeyPressed(.down)) {
            self.movePlayerBackward(dt);
        }

        if (keyboard_state.isKeyPressed(.a) or keyboard_state.isKeyPressed(.left)) {
            self.rotatePlayerLeft(dt);
        }

        if (keyboard_state.isKeyPressed(.d) or keyboard_state.isKeyPressed(.right)) {
            self.rotatePlayerRight(dt);
        }

        if (keyboard_state.isKeyPressed(.q)) {
            self.strafePlayerLeft(dt);
        }

        if (keyboard_state.isKeyPressed(.e)) {
            self.strafePlayerRight(dt);
        }
    }

    fn movePlayerForward(self: *Self, dt: f32) void {
        const new_pos = self.player.position.add(self.player.direction.mulScalar(Player.move_speed * dt));

        const map_x = @as(i32, @intFromFloat(@trunc(new_pos.x)));
        const map_y = @as(i32, @intFromFloat(@trunc(new_pos.y)));

        if (self.map.getTile(map_x, map_y) == .Empty) {
            self.player.moveForward(dt, 1.0);
        }
    }

    fn movePlayerBackward(self: *Self, dt: f32) void {
        const new_pos = self.player.position.add(self.player.direction.mulScalar(-Player.move_speed * dt));

        const map_x = @as(i32, @intFromFloat(@trunc(new_pos.x)));
        const map_y = @as(i32, @intFromFloat(@trunc(new_pos.y)));

        if (self.map.getTile(map_x, map_y) == .Empty) {
            self.player.moveBackward(dt, 1.0);
        }
    }

    fn strafePlayerLeft(self: *Self, dt: f32) void {
        const new_pos = self.player.position.add(self.camera.plane.mulScalar(-Player.move_speed * dt));

        const map_x = @as(i32, @intFromFloat(@trunc(new_pos.x)));
        const map_y = @as(i32, @intFromFloat(@trunc(new_pos.y)));

        if (self.map.getTile(map_x, map_y) == .Empty) {
            self.player.strafeLeft(dt, 1.0, self.camera.plane);
        }
    }

    fn strafePlayerRight(self: *Self, dt: f32) void {
        const new_pos = self.player.position.add(self.camera.plane.mulScalar(Player.move_speed * dt));

        const map_x = @as(i32, @intFromFloat(@trunc(new_pos.x)));
        const map_y = @as(i32, @intFromFloat(@trunc(new_pos.y)));

        if (self.map.getTile(map_x, map_y) == .Empty) {
            self.player.strafeRight(dt, 1.0, self.camera.plane);
        }
    }

    fn rotatePlayerLeft(self: *Self, dt: f32) void {
        self.player.rotate(dt, 1.0, &self.camera.plane);
    }

    fn rotatePlayerRight(self: *Self, dt: f32) void {
        self.player.rotate(dt, -1.0, &self.camera.plane);
    }

    pub fn rasterize(self: Self, texture_buffer: *TextureBuffer) void {
        texture_buffer.clear(color.getColor(.Black));

        const screen_width = texture_buffer.width;
        const screen_height = texture_buffer.height;
        const screen_height_f32: f32 = @floatFromInt(screen_height);
        const screen_width_f32: f32 = @floatFromInt(screen_width);
        const half_screen_height = uToI32(screen_height) >> 1;

        for (0..screen_height) |y_usize| {
            const y: u32 = @intCast(y_usize);

            const ray_dir_0 = Vec2.init(
                self.player.direction.x - self.camera.plane.x,
                self.player.direction.y - self.camera.plane.y,
            );
            const ray_dir_1 = Vec2.init(
                self.player.direction.x + self.camera.plane.x,
                self.player.direction.y + self.camera.plane.y,
            );

            const position_y = @as(i32, @intCast(y)) - half_screen_height;
            if (position_y == 0) continue;
            const position_z: f32 = @floatFromInt(half_screen_height);

            const row_distance = position_z / @as(f32, @floatFromInt(position_y));

            const floor_step_x = row_distance * (ray_dir_1.x - ray_dir_0.x) / screen_width_f32;
            const floor_step_y = row_distance * (ray_dir_1.y - ray_dir_0.y) / screen_width_f32;

            var floor_x = self.player.position.x + row_distance * ray_dir_0.x;
            var floor_y = self.player.position.y + row_distance * ray_dir_0.y;

            for (0..screen_width) |x_usize| {
                const cell_x = @floor(floor_x);
                const cell_y = @floor(floor_y);

                const frac_x = floor_x - cell_x;
                const frac_y = floor_y - cell_y;

                var texture_x: u32 = @intFromFloat(@floor(frac_x * 64.0));
                var texture_y: u32 = @intFromFloat(@floor(frac_y * 64.0));

                texture_x &= 64 - 1;
                texture_y &= 64 - 1;

                floor_x += floor_step_x;
                floor_y += floor_step_y;

                var floor_color = sample(self.map.textures.items[0].data, texture_x, texture_y);

                floor_color[0] /= 2;
                floor_color[1] /= 2;
                floor_color[2] /= 2;

                texture_buffer.drawPixel(@intCast(x_usize), @intCast(y), .{
                    .r = @as(f32, @floatFromInt(floor_color[0])) / 255.0,
                    .g = @as(f32, @floatFromInt(floor_color[1])) / 255.0,
                    .b = @as(f32, @floatFromInt(floor_color[2])) / 255.0,
                    .a = @as(f32, @floatFromInt(floor_color[3])) / 255.0,
                });

                var ceiling_color = sample(self.map.textures.items[1].data, texture_x, texture_y);

                ceiling_color[0] /= 1;
                ceiling_color[1] /= 1;
                ceiling_color[2] /= 1;

                texture_buffer.drawPixel(@intCast(x_usize), @as(i32, @intCast(screen_height)) - @as(i32, @intCast(y)) - 1, .{
                    .r = @as(f32, @floatFromInt(ceiling_color[0])) / 255.0,
                    .g = @as(f32, @floatFromInt(ceiling_color[1])) / 255.0,
                    .b = @as(f32, @floatFromInt(ceiling_color[2])) / 255.0,
                    .a = @as(f32, @floatFromInt(ceiling_color[3])) / 255.0,
                });
            }
        }

        for (0..screen_width) |x_usize| {
            const x_f32: f32 = @floatFromInt(x_usize);

            const camera_x = 2.0 * x_f32 / screen_width_f32 - 1.0;
            const ray_dir = self.player.direction.add(self.camera.plane.mulScalar(camera_x));

            var map_position = Vec2.init(
                @trunc(self.player.position.x),
                @trunc(self.player.position.y),
            );

            var side_dist = Vec2.init(0.0, 0.0);
            const delta_dist = Vec2.init(
                if (ray_dir.x == 0.0) 1e30 else @abs(1.0 / ray_dir.x),
                if (ray_dir.y == 0.0) 1e30 else @abs(1.0 / ray_dir.y),
            );

            var step = Vec2.init(0.0, 0.0);
            var hit = false;
            var side: i32 = 0;

            if (ray_dir.x < 0.0) {
                step.x = -1.0;
                side_dist.x = (self.player.position.x - map_position.x) * delta_dist.x;
            } else {
                step.x = 1.0;
                side_dist.x = (map_position.x + 1.0 - self.player.position.x) * delta_dist.x;
            }

            if (ray_dir.y < 0.0) {
                step.y = -1.0;
                side_dist.y = (self.player.position.y - map_position.y) * delta_dist.y;
            } else {
                step.y = 1.0;
                side_dist.y = (map_position.y + 1.0 - self.player.position.y) * delta_dist.y;
            }

            var tile: Tile = .Empty;

            while (!hit) {
                if (side_dist.x < side_dist.y) {
                    side_dist.x += delta_dist.x;
                    map_position.x += step.x;
                    side = 0;
                } else {
                    side_dist.y += delta_dist.y;
                    map_position.y += step.y;
                    side = 1;
                }

                const map_x = f32ToI32(map_position.x);
                const map_y = f32ToI32(map_position.y);

                tile = self.map.getTile(map_x, map_y);

                if (tile != .Empty) {
                    hit = true;
                }
            }

            if (hit) {
                var perp_wall_dist: f32 = 0.0;

                if (side == 0) {
                    perp_wall_dist = (map_position.x - self.player.position.x + (1.0 - step.x) / 2.0) / ray_dir.x;
                } else {
                    perp_wall_dist = (map_position.y - self.player.position.y + (1.0 - step.y) / 2.0) / ray_dir.y;
                }

                const safe_dist = @max(perp_wall_dist, 0.0001); // Prevent division by very small values
                const height_ratio: f32 = screen_height_f32 / safe_dist;
                const line_height = f32ToI32(height_ratio);

                const half_line_height = line_height >> 1;

                var draw_start = -half_line_height + half_screen_height;
                draw_start = @max(0, draw_start);

                var draw_end = half_line_height + half_screen_height;
                draw_end = @min(uToI32(screen_height) - 1, draw_end);

                var wall_x = if (side == 0)
                    self.player.position.y + perp_wall_dist * ray_dir.y
                else
                    self.player.position.x + perp_wall_dist * ray_dir.x;

                wall_x -= @floor(wall_x);

                var texture_x: u32 = @intFromFloat(@trunc(wall_x * 64));

                if ((side == 0 and ray_dir.x > 0) or (side == 1 and ray_dir.y < 0)) {
                    texture_x = 64 - texture_x - 1;
                }

                const step_y = 1.0 * 64 / @as(f32, @floatFromInt(line_height));
                var texture_position = @as(f32, @floatFromInt(draw_start - half_screen_height + half_line_height)) * step_y;

                for (@intCast(draw_start)..@intCast(draw_end)) |y| {
                    const texture_y: u32 = @as(u32, @intFromFloat(texture_position)) & (64 - 1);
                    texture_position += step_y;

                    const texture_color = sample(self.map.textures.items[2].data, texture_x, texture_y);

                    var n = Vec2.init(0.0, 0.0);

                    if (side == 0) {
                        n.x = -step.x;
                        n.y = 0.0;
                    } else {
                        n.x = 0.0;
                        n.y = -step.y;
                    }

                    // directional light
                    const ambient = 0.1;
                    const diffuse = 0.5;

                    const lambert = @max(0, n.dot(self.light_dir));
                    const falloff = 1.0;
                    const light = @min(1.0, ambient + diffuse * lambert) * falloff;

                    const lr = @min(255.0, @as(f32, @floatFromInt(texture_color[0])) * light);
                    const lg = @min(255.0, @as(f32, @floatFromInt(texture_color[1])) * light);
                    const lb = @min(255.0, @as(f32, @floatFromInt(texture_color[2])) * light);

                    texture_buffer.drawPixel(@intCast(x_usize), @intCast(y), .{
                        .r = lr / 255.0,
                        .g = lg / 255.0,
                        .b = lb / 255.0,
                        .a = @as(f32, @floatFromInt(texture_color[3])) / 255.0,
                    });
                }
            }
        }
    }
};

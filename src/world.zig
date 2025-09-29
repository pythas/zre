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
const lighting = @import("lighting.zig");

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
    map: *Map,
    player: Player,
    camera: Camera,

    pub fn init(allocator: std.mem.Allocator, map: *Map) !Self {
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
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
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

        if (self.map.getTile(map_x, map_y).kind == .Empty) {
            self.player.moveForward(dt, 1.0);
        }
    }

    fn movePlayerBackward(self: *Self, dt: f32) void {
        const new_pos = self.player.position.add(self.player.direction.mulScalar(-Player.move_speed * dt));

        const map_x = @as(i32, @intFromFloat(@trunc(new_pos.x)));
        const map_y = @as(i32, @intFromFloat(@trunc(new_pos.y)));

        if (self.map.getTile(map_x, map_y).kind == .Empty) {
            self.player.moveBackward(dt, 1.0);
        }
    }

    fn strafePlayerLeft(self: *Self, dt: f32) void {
        const new_pos = self.player.position.add(self.camera.plane.mulScalar(-Player.move_speed * dt));

        const map_x = @as(i32, @intFromFloat(@trunc(new_pos.x)));
        const map_y = @as(i32, @intFromFloat(@trunc(new_pos.y)));

        if (self.map.getTile(map_x, map_y).kind == .Empty) {
            self.player.strafeLeft(dt, 1.0, self.camera.plane);
        }
    }

    fn strafePlayerRight(self: *Self, dt: f32) void {
        const new_pos = self.player.position.add(self.camera.plane.mulScalar(Player.move_speed * dt));

        const map_x = @as(i32, @intFromFloat(@trunc(new_pos.x)));
        const map_y = @as(i32, @intFromFloat(@trunc(new_pos.y)));

        if (self.map.getTile(map_x, map_y).kind == .Empty) {
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

        const rs = self.map.render_settings;

        // Plane & wall lighting: ambient + per-light diffuse with attenuation.
        const ambient_color = self.map.lightning.ambient;
        const base_ambient_r: f32 = ambient_color[0] * rs.ambient_plane;
        const base_ambient_g: f32 = ambient_color[1] * rs.ambient_plane;
        const base_ambient_b: f32 = ambient_color[2] * rs.ambient_plane;

        // Iterate only bottom half and mirror for ceiling.
        for (@as(usize, @intCast(half_screen_height + 1))..screen_height) |y_usize| {
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
            if (position_y == 0) {
                continue;
            } // Should not happen because we start at half + 1

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

                const floor_world_z: f32 = 0.0;
                const ceiling_height: f32 = 1.0;
                const ceiling_world_z: f32 = ceiling_height;
                const world_x: f32 = @floatCast(cell_x + frac_x);
                const world_y: f32 = @floatCast(cell_y + frac_y);

                // Floor lighting
                const floor_acc = lighting.accumulatePlaneLights(self.map.lightning.lights.items, 1.0, world_x, world_y, floor_world_z, rs.diffuse_plane);
                const floor_factor_r = std.math.clamp(base_ambient_r + floor_acc.r, 0.0, 1.0);
                const floor_factor_g = std.math.clamp(base_ambient_g + floor_acc.g, 0.0, 1.0);
                const floor_factor_b = std.math.clamp(base_ambient_b + floor_acc.b, 0.0, 1.0);
                const floor_texture_data = self.map.textures.items[self.map.floor].data;
                const floor_color = sample(floor_texture_data, texture_x, texture_y);
                const fr = @min(255.0, @as(f32, @floatFromInt(floor_color[0])) * floor_factor_r);
                const fg = @min(255.0, @as(f32, @floatFromInt(floor_color[1])) * floor_factor_g);
                const fb = @min(255.0, @as(f32, @floatFromInt(floor_color[2])) * floor_factor_b);
                const fogged_floor = lighting.applyFog(rs.fog.enabled, rs.fog.color, rs.fog.density, row_distance, fr, fg, fb);

                texture_buffer.drawPixel(@intCast(x_usize), @intCast(y), .{
                    .r = fogged_floor[0] / 255.0,
                    .g = fogged_floor[1] / 255.0,
                    .b = fogged_floor[2] / 255.0,
                    .a = @as(f32, @floatFromInt(floor_color[3])) / 255.0,
                });

                // Ceiling lighting (fallback tints with floor if totally dark)
                const ceiling_acc = lighting.accumulatePlaneLights(self.map.lightning.lights.items, -1.0, world_x, world_y, ceiling_world_z, rs.diffuse_plane);
                var ceiling_factor_r = base_ambient_r + ceiling_acc.r;
                var ceiling_factor_g = base_ambient_g + ceiling_acc.g;
                var ceiling_factor_b = base_ambient_b + ceiling_acc.b;
                if (ceiling_acc.r == 0.0 and ceiling_acc.g == 0.0 and ceiling_acc.b == 0.0) {
                    // use floor_acc for fallback tint
                    ceiling_factor_r = base_ambient_r + floor_acc.r * 0.7;
                    ceiling_factor_g = base_ambient_g + floor_acc.g * 0.7;
                    ceiling_factor_b = base_ambient_b + floor_acc.b * 0.7;
                }
                ceiling_factor_r = std.math.clamp(ceiling_factor_r, 0.0, 1.0);
                ceiling_factor_g = std.math.clamp(ceiling_factor_g, 0.0, 1.0);
                ceiling_factor_b = std.math.clamp(ceiling_factor_b, 0.0, 1.0);
                const ceiling_texture_data = self.map.textures.items[self.map.ceiling].data;
                const ceiling_color = sample(ceiling_texture_data, texture_x, texture_y);
                const cr = @min(255.0, @as(f32, @floatFromInt(ceiling_color[0])) * ceiling_factor_r);
                const cg = @min(255.0, @as(f32, @floatFromInt(ceiling_color[1])) * ceiling_factor_g);
                const cb = @min(255.0, @as(f32, @floatFromInt(ceiling_color[2])) * ceiling_factor_b);
                const fogged_ceiling = lighting.applyFog(rs.fog.enabled, rs.fog.color, rs.fog.density, row_distance, cr, cg, cb);

                texture_buffer.drawPixel(
                    @intCast(x_usize),
                    @as(i32, @intCast(screen_height)) - @as(i32, @intCast(y)) - 1,
                    .{
                        .r = fogged_ceiling[0] / 255.0,
                        .g = fogged_ceiling[1] / 255.0,
                        .b = fogged_ceiling[2] / 255.0,
                        .a = @as(f32, @floatFromInt(ceiling_color[3])) / 255.0,
                    },
                );
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

            var tile = Tile.initEmpty();

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

                if (tile.kind != .Empty) {
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

                const n: Vec2 = if (side == 0)
                    Vec2.init(-step.x, 0.0)
                else
                    Vec2.init(0.0, -step.y);

                // Wall lighting
                const hit_point = self.player.position.add(ray_dir.mulScalar(perp_wall_dist));
                var wall_acc = lighting.accumulateWallLights(
                    self.map.lightning.lights.items,
                    n,
                    hit_point,
                    rs.player_height,
                    rs.light_height_bias,
                    rs.diffuse_wall,
                );
                wall_acc.r += base_ambient_r;
                wall_acc.g += base_ambient_g;
                wall_acc.b += base_ambient_b;

                wall_acc.clamp01();

                for (@intCast(draw_start)..@intCast(draw_end)) |y| {
                    const texture_y: u32 = @as(u32, @intFromFloat(texture_position)) & (64 - 1);
                    texture_position += step_y;

                    const texture_data = self.map.textures.items[tile.texture.?].data;
                    const texture_color = sample(texture_data, texture_x, texture_y);

                    const lr0 = @min(255.0, @as(f32, @floatFromInt(texture_color[0])) * wall_acc.r);
                    const lg0 = @min(255.0, @as(f32, @floatFromInt(texture_color[1])) * wall_acc.g);
                    const lb0 = @min(255.0, @as(f32, @floatFromInt(texture_color[2])) * wall_acc.b);
                    const fogged_wall = lighting.applyFog(rs.fog.enabled, rs.fog.color, rs.fog.density, perp_wall_dist, lr0, lg0, lb0);

                    texture_buffer.drawPixel(@intCast(x_usize), @intCast(y), .{
                        .r = fogged_wall[0] / 255.0,
                        .g = fogged_wall[1] / 255.0,
                        .b = fogged_wall[2] / 255.0,
                        .a = @as(f32, @floatFromInt(texture_color[3])) / 255.0,
                    });
                }
            }
        }
    }
};

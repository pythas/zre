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

// TODO: Move these helper functions to a utility file
fn f32ToI32(value: f32) i32 {
    return @intFromFloat(@min(value, @as(f32, @floatFromInt(math.maxInt(i32)))));
}

fn uToI32(value: anytype) i32 {
    return @intCast(value);
}

pub const World = struct {
    const Self = @This();

    map: Map,
    player: Player,
    camera: Camera,

    pub fn init(allocator: std.mem.Allocator, map_source: MapSource) !Self {
        const map = switch (map_source) {
            .path => |path| try Map.initFromPath(allocator, path),
            .json => |path| try Map.initFromJson(allocator, path),
        };

        const player = try Player.init(
            Vec2.init(7.5, 7.5),
            Vec2.init(-1.0, 0.0),
        );

        const camera = try Camera.init(
            Vec2.init(0.0, 0.66),
        );

        return .{
            .map = map,
            .player = player,
            .camera = camera,
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

        for (0..screen_width) |x_usize| {
            const x_i32 = uToI32(x_usize);
            const x_f32: f32 = @floatFromInt(x_usize);
            const screen_width_f32: f32 = @floatFromInt(screen_width);

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
                const screen_height_f32: f32 = @floatFromInt(screen_height);
                const height_ratio: f32 = screen_height_f32 / safe_dist;
                const line_height = f32ToI32(height_ratio);

                const half_line_height = line_height >> 1;
                const half_screen_height = uToI32(screen_height) >> 1;

                var draw_start = -half_line_height + half_screen_height;
                draw_start = @max(0, draw_start);

                var draw_end = half_line_height + half_screen_height;
                draw_end = @min(uToI32(screen_height) - 1, draw_end);

                switch (tile) {
                    .Wall => texture_buffer.drawVerticalLineSegment(x_i32, draw_start, draw_end, color.getColor(.White)),
                    .AnotherWall => texture_buffer.drawVerticalLineSegment(x_i32, draw_start, draw_end, color.getColor(.Red)),
                    else => {},
                }
            }
        }
    }
};

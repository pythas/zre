const std = @import("std");
const zgpu = @import("zgpu");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

const Vec2 = @import("vec2.zig").Vec2;
const Player = @import("player.zig").Player;
const Map = @import("map.zig").Map;
const MapResult = @import("map.zig").MapResult;
const Camera = @import("camera.zig").Camera;

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

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    map: *Map,
    player: Player,
    camera: Camera,

    pub fn init(allocator: std.mem.Allocator, map_result: *MapResult) !Self {
        const player = try Player.init(
            Vec2.init(map_result.player_position[0], map_result.player_position[1]),
            Vec2.init(map_result.player_direction[0], map_result.player_direction[1]),
        );

        const camera = try Camera.init(
            Vec2.init(0.0, 0.66),
        );

        return .{
            .allocator = allocator,
            .map = &map_result.map,
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
};

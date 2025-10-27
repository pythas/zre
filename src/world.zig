const std = @import("std");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

const Vec2 = @import("vec2.zig").Vec2;
const Player = @import("player.zig").Player;
const Map = @import("map.zig").Map;
const MapResult = @import("map.zig").MapResult;
const Camera = @import("camera.zig").Camera;
const Entity = @import("entity.zig").Entity;
const Tile = @import("map.zig").Tile;

pub const MapSource = union(enum) {
    path: []const u8,
    json: []const u8,
};

pub const KeyboardState = struct {
    const Self = @This();

    window: *zglfw.Window,

    curr: u16 = 0,
    prev: u16 = 0,

    pub const Key = enum(u4) {
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

    pub fn init(window: *zglfw.Window) Self {
        return .{
            .window = window,
        };
    }

    pub fn beginFrame(self: *Self) void {
        self.prev = self.curr;
        self.curr = 0;

        if (self.window.getKey(.w) == .press) self.curr |= bit(.w);
        if (self.window.getKey(.a) == .press) self.curr |= bit(.a);
        if (self.window.getKey(.s) == .press) self.curr |= bit(.s);
        if (self.window.getKey(.d) == .press) self.curr |= bit(.d);
        if (self.window.getKey(.q) == .press) self.curr |= bit(.q);
        if (self.window.getKey(.e) == .press) self.curr |= bit(.e);
        if (self.window.getKey(.up) == .press) self.curr |= bit(.up);
        if (self.window.getKey(.down) == .press) self.curr |= bit(.down);
        if (self.window.getKey(.left) == .press) self.curr |= bit(.left);
        if (self.window.getKey(.right) == .press) self.curr |= bit(.right);
    }

    pub fn isDown(self: *const Self, k: Key) bool {
        return (self.curr & bit(k)) != 0;
    }
    pub fn wasDown(self: *const Self, k: Key) bool {
        return (self.prev & bit(k)) != 0;
    }

    pub fn isPressed(self: *const Self, k: Key) bool {
        return self.isDown(k) and !self.wasDown(k);
    }

    pub fn isReleased(self: *const Self, k: Key) bool {
        return !self.isDown(k) and self.wasDown(k);
    }

    inline fn bit(k: Key) u16 {
        return @as(u16, 1) << @intFromEnum(k);
    }
};

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    map: Map,
    player: Player,
    camera: Camera,
    entities: std.ArrayList(Entity),

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
            .map = map_result.map,
            .player = player,
            .camera = camera,
            .entities = map_result.entities,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn update(self: *Self, dt: f32, keyboard_state: *const KeyboardState) void {
        if (keyboard_state.isDown(.w)) {
            self.movePlayerForward(dt);
        }

        if (keyboard_state.isDown(.s)) {
            self.movePlayerBackward(dt);
        }

        if (keyboard_state.isDown(.a)) {
            self.rotatePlayerLeft(dt);
        }

        if (keyboard_state.isDown(.d)) {
            self.rotatePlayerRight(dt);
        }

        // if (keyboard_state.isKeyPressed(.q)) {
        //     self.strafePlayerLeft(dt);
        // }
        //
        // if (keyboard_state.isKeyPressed(.e)) {
        //     self.strafePlayerRight(dt);
        // }

        if (keyboard_state.isPressed(.e)) {
            self.interactWithDoor();
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

    fn interactWithDoor(self: *Self) void {
        const player_x = @as(i32, @intFromFloat(self.player.position.x));
        const player_y = @as(i32, @intFromFloat(self.player.position.y));

        for (self.entities.items) |*entity| {
            switch (entity.*) {
                .door => |*door| {
                    const door_x = @as(i32, @intFromFloat(door.position.x));
                    const door_y = @as(i32, @intFromFloat(door.position.y));

                    if (player_x == door_x and player_y == door_y) {
                        continue;
                    }

                    const dx = player_x - door_x;
                    const dy = player_y - door_y;

                    const manhattan = @abs(dx) + @abs(dy);

                    if (manhattan != 1) {
                        continue;
                    }

                    var tile = self.map.getTile(door_x, door_y);

                    if (door.state == .open) {
                        door.state = .closed;
                        tile.kind = .Wall;
                        self.map.updateTile(door_x, door_y, tile);
                    } else if (door.state == .closed) {
                        door.state = .open;
                        tile.kind = .Empty;
                        self.map.updateTile(door_x, door_y, tile);
                    }

                    self.map.is_dirty = true;
                },
            }
        }
    }
};

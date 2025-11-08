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
const MouseGesture = @import("input.zig").MouseGesture;

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
        r,
        f,
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
        if (self.window.getKey(.r) == .press) self.curr |= bit(.r);
        if (self.window.getKey(.f) == .press) self.curr |= bit(.f);
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
    // prev_mouse_x: f32 = 0.0,
    // prev_mouse_y: f32 = 0.0,
    active_gesture: ?MouseGesture = null,

    pub fn init(allocator: std.mem.Allocator, map_result: *MapResult) !Self {
        const player = try Player.init(
            Vec2.init(map_result.player_position[0], map_result.player_position[1]),
            Vec2.init(map_result.player_direction[0], map_result.player_direction[1]),
        );

        // Camera plane should be perpendicular to player direction with FOV factor
        const direction = Vec2.init(map_result.player_direction[0], map_result.player_direction[1]);
        const plane = direction.perpendicular().mulScalar(0.66);

        const camera = try Camera.init(plane);

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

    pub fn update(
        self: *Self,
        dt: f32,
        keyboard_state: *const KeyboardState,
        window: *zglfw.Window,
    ) void {
        self.player.update(dt, &self.camera.plane);

        const mouse_pos = window.getCursorPos();
        const mouse_x: f32 = @floatCast(mouse_pos[0]);
        const mouse_y: f32 = @floatCast(mouse_pos[1]);
        const left_button = window.getMouseButton(.left);

        if (left_button == .press) {
            if (self.active_gesture == null) {
                self.active_gesture = MouseGesture.init(mouse_x, mouse_y);
            } else {
                self.active_gesture.?.update(mouse_x, mouse_y);
            }
        } else if (left_button == .release and self.active_gesture != null) {
            if (self.active_gesture.?.detectGesture()) |gesture_type| {
                self.player.startAttack(gesture_type);
            }

            self.active_gesture = null;
        }

        if (self.player.isAnimating()) {
            return;
        }

        if (keyboard_state.isPressed(.w)) {
            self.tryMovePlayerForward();
        }

        if (keyboard_state.isPressed(.s)) {
            self.tryMovePlayerBackward();
        }

        if (keyboard_state.isPressed(.a)) {
            self.tryMovePlayerLeft();
        }

        if (keyboard_state.isPressed(.d)) {
            self.tryMovePlayerRight();
        }

        if (keyboard_state.isPressed(.q)) {
            self.turnPlayerLeft();
        }

        if (keyboard_state.isPressed(.e)) {
            self.turnPlayerRight();
        }

        if (keyboard_state.isPressed(.r) or keyboard_state.isPressed(.f)) {
            self.interactWithDoor();
        }
    }

    fn tryMovePlayerForward(self: *Self) void {
        const current_x = @as(i32, @intFromFloat(@floor(self.player.position.x)));
        const current_y = @as(i32, @intFromFloat(@floor(self.player.position.y)));

        const target_x = current_x + @as(i32, @intFromFloat(@round(self.player.direction.x)));
        const target_y = current_y + @as(i32, @intFromFloat(@round(self.player.direction.y)));

        if (self.map.getTile(target_x, target_y).kind == .Empty) {
            const target_pos = Vec2.init(
                @as(f32, @floatFromInt(target_x)) + 0.5,
                @as(f32, @floatFromInt(target_y)) + 0.5,
            );
            self.player.startMove(target_pos);
        }
    }

    fn tryMovePlayerBackward(self: *Self) void {
        const current_x = @as(i32, @intFromFloat(@floor(self.player.position.x)));
        const current_y = @as(i32, @intFromFloat(@floor(self.player.position.y)));

        const target_x = current_x - @as(i32, @intFromFloat(@round(self.player.direction.x)));
        const target_y = current_y - @as(i32, @intFromFloat(@round(self.player.direction.y)));

        if (self.map.getTile(target_x, target_y).kind == .Empty) {
            const target_pos = Vec2.init(
                @as(f32, @floatFromInt(target_x)) + 0.5,
                @as(f32, @floatFromInt(target_y)) + 0.5,
            );
            self.player.startMove(target_pos);
        }
    }

    fn tryMovePlayerLeft(self: *Self) void {
        const current_x = @as(i32, @intFromFloat(@floor(self.player.position.x)));
        const current_y = @as(i32, @intFromFloat(@floor(self.player.position.y)));

        const left = self.camera.plane.mulScalar(-1.0).normalize();
        const target_x = current_x + @as(i32, @intFromFloat(@round(left.x)));
        const target_y = current_y + @as(i32, @intFromFloat(@round(left.y)));

        if (self.map.getTile(target_x, target_y).kind == .Empty) {
            const target_pos = Vec2.init(
                @as(f32, @floatFromInt(target_x)) + 0.5,
                @as(f32, @floatFromInt(target_y)) + 0.5,
            );
            self.player.startMove(target_pos);
        }
    }

    fn tryMovePlayerRight(self: *Self) void {
        const current_x = @as(i32, @intFromFloat(@floor(self.player.position.x)));
        const current_y = @as(i32, @intFromFloat(@floor(self.player.position.y)));

        const right = self.camera.plane.normalize();
        const target_x = current_x + @as(i32, @intFromFloat(@round(right.x)));
        const target_y = current_y + @as(i32, @intFromFloat(@round(right.y)));

        if (self.map.getTile(target_x, target_y).kind == .Empty) {
            const target_pos = Vec2.init(
                @as(f32, @floatFromInt(target_x)) + 0.5,
                @as(f32, @floatFromInt(target_y)) + 0.5,
            );
            self.player.startMove(target_pos);
        }
    }

    fn turnPlayerLeft(self: *Self) void {
        const turn_angle = std.math.pi / 2.0;
        self.player.startTurn(turn_angle, self.camera.plane);
    }

    fn turnPlayerRight(self: *Self) void {
        const turn_angle = -std.math.pi / 2.0;
        self.player.startTurn(turn_angle, self.camera.plane);
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

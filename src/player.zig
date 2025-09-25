const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;

pub const Player = struct {
    const Self = @This();

    pub const move_speed: f32 = 3.0;
    pub const rotation_speed: f32 = 2.0;

    position: Vec2,
    direction: Vec2,

    pub fn init(position: Vec2, direction: Vec2) !Self {
        return .{
            .position = position,
            .direction = direction,
        };
    }

    pub fn moveForward(self: *Self, dt: f32, distance: f32) void {
        const move_vec = self.direction.mulScalar(distance * dt * move_speed);
        self.position = self.position.add(move_vec);
    }

    pub fn moveBackward(self: *Self, dt: f32, distance: f32) void {
        const move_vec = self.direction.mulScalar(-distance * dt * move_speed);
        self.position = self.position.add(move_vec);
    }

    pub fn strafeLeft(self: *Self, dt: f32, distance: f32, plane: Vec2) void {
        const move_vec = plane.mulScalar(-distance * dt * move_speed);
        self.position = self.position.add(move_vec);
    }

    pub fn strafeRight(self: *Self, dt: f32, distance: f32, plane: Vec2) void {
        const move_vec = plane.mulScalar(distance * dt * move_speed);
        self.position = self.position.add(move_vec);
    }

    pub fn rotate(self: *Self, dt: f32, angle: f32, plane: *Vec2) void {
        const rotation_amount = angle * dt * rotation_speed;
        self.direction.rotate(rotation_amount);
        plane.rotate(rotation_amount);
    }
};

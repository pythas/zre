const std = @import("std");
const Vec2 = @import("vec2.zig").Vec2;
const AttackType = @import("player.zig").AttackType;

pub const MouseGesture = struct {
    const Self = @This();

    start_pos: Vec2,
    current_pos: Vec2,
    is_active: bool,
    min_distance: f32 = 50.0,

    pub fn init(mouse_x: f32, mouse_y: f32) MouseGesture {
        return .{
            .start_pos = Vec2.init(mouse_x, mouse_y),
            .current_pos = Vec2.init(mouse_x, mouse_y),
            .is_active = true,
        };
    }

    pub fn update(self: *Self, mouse_x: f32, mouse_y: f32) void {
        self.current_pos = Vec2.init(mouse_x, mouse_y);
    }

    pub fn detectGesture(self: MouseGesture) ?AttackType {
        const delta = self.current_pos.sub(self.start_pos);
        const distance = delta.len();

        if (distance < self.min_distance) {
            return null;
        }

        const angle = std.math.atan2(delta.y, delta.x);
        const abs_angle = @abs(angle);

        if (abs_angle < std.math.pi / 4.0 or abs_angle > 3.0 * std.math.pi / 4.0) {
            return .horizontal_slash;
        }

        if (angle > std.math.pi / 4.0 and angle < 3.0 * std.math.pi / 4.0) {
            return .overhead_strike;
        }

        if (angle < -std.math.pi / 4.0 and angle > -3.0 * std.math.pi / 4.0) {
            return .thrust;
        }

        return null;
    }
};

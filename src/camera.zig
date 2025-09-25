const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;

pub const Camera = struct {
    const Self = @This();

    plane: Vec2,

    pub fn init(plane: Vec2) !Self {
        return .{
            .plane = plane,
        };
    }
};

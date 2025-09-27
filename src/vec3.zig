const std = @import("std");

pub const Vec3 = struct {
    const Self = @This();

    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Self {
        return .{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn normalize(self: Self) Self {
        const len = std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
        if (len == 0.0) {
            return self;
        }
        return .{
            .x = self.x / len,
            .y = self.y / len,
            .z = self.z / len,
        };
    }

    pub fn neg(self: Self) Self {
        return .{
            .x = -self.x,
            .y = -self.y,
            .z = -self.z,
        };
    }
};

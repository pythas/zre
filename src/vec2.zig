pub const Vec2 = struct {
    const Self = @This();

    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(self: Self, other: Self) Self {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Self, other: Self) Self {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn mulScalar(self: Self, scalar: f32) Self {
        return .{ .x = self.x * scalar, .y = self.y * scalar };
    }

    pub fn rotate(self: *Self, amount: f32) void {
        const old_x = self.x;
        self.x = self.x * @cos(amount) - self.y * @sin(amount);
        self.y = old_x * @sin(amount) + self.y * @cos(amount);
    }
};

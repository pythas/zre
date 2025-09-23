const std = @import("std");

pub const Player = struct {
    const Self = @This();

    pub fn init(_: std.mem.Allocator) !Self {
        return .{};
    }
};

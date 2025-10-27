const std = @import("std");
const Vec2 = @import("vec2.zig").Vec2;

pub const Entity = union(enum) {
    door: DoorEntity,

    pub const DoorEntity = struct {
        const Self = @This();

        pub const DoorState = enum {
            open,
            closed,
            locked,
        };

        position: Vec2,
        state: DoorState,

        pub fn init(position: Vec2, state: DoorState) Self {
            return .{
                .position = position,
                .state = state,
            };
        }

        pub fn stateFromString(state: []const u8) ?DoorState {
            if (std.mem.eql(u8, state, "open")) {
                return .open;
            }

            if (std.mem.eql(u8, state, "closed")) {
                return .closed;
            }

            if (std.mem.eql(u8, state, "locked")) {
                return .closed;
            }

            return null;
        }
    };
};

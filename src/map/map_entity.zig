const Self = @This();

pub const MapEntityKind = enum {
    Player,
    Monster,
    Item,
};

pub const MapEntityEnum = union(enum) {
    Player,
};

kind: u32,
x: f32,
y: f32,
z: f32,
angle: f32,

pub fn init(kind: u32, x: f32, y: f32, z: f32, angle: f32) Self {
    return .{
        .kind = kind,
        .x = x,
        .y = y,
        .z = z,
        .angle = angle,
    };
}

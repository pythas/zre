const Self = @This();
const Sector = @import("../sector.zig");

floor_height: f32,
ceiling_height: f32,

pub fn init(floor_height: f32, ceiling_height: f32) Self {
    return .{
        .floor_height = floor_height,
        .ceiling_height = ceiling_height,
    };
}

pub fn fromSector(sector: Sector) Self {
    return Self.init(sector.floor_height, sector.ceiling_height);
}

pub fn toSector(self: Self) Sector {
    return Sector.init(self.floor_height, self.ceiling_height);
}

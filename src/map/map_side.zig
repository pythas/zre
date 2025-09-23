const Self = @This();
const Side = @import("../side.zig");

sector: usize,

pub fn init(sector: usize) Self {
    return .{
        .sector = sector,
    };
}

pub fn toSide(self: Self) Side {
    return Side.init(self.sector);
}

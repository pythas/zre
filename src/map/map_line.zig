const Self = @This();
const Map = @import("../map.zig");
const MapSide = @import("map_side.zig");
const MapVertex = @import("map_vertex.zig");
const Line = @import("../line.zig");
const LineSegment = @import("../line_segment.zig");
const Side = @import("../side.zig");

start: usize,
end: usize,
side_a: ?MapSide = null,
side_b: ?MapSide = null,

pub fn init(
    start: usize,
    end: usize,
    side_a: ?MapSide,
    side_b: ?MapSide,
) Self {
    return .{
        .start = start,
        .end = end,
        .side_a = side_a,
        .side_b = side_b,
    };
}

pub fn toLine(self: Self) Line {
    const side_a = if (self.side_a != null) self.side_a.?.toSide() else null;
    const side_b = if (self.side_b != null) self.side_b.?.toSide() else null;

    return Line.init(self.start, self.end, side_a, side_b);
}

pub fn toLineSegment(self: Self, map: Map) LineSegment {
    const line = self.toLine();

    return LineSegment.init(
        MapVertex.createVertexFromMap(map, line.start),
        MapVertex.createVertexFromMap(map, line.end),
        line.side_a,
        line.side_b,
    );
}

pub fn createLineFromMap(map: Map, index: usize) Line {
    const start = map.lines[index].start;
    const end = map.lines[index].end;
    const side_a = if (map.lines[index].side_a != null) map.lines[index].side_a.?.toSide() else null;
    const side_b = if (map.lines[index].side_b != null) map.lines[index].side_b.?.toSide() else null;

    return Line.init(start, end, side_a, side_b);
}

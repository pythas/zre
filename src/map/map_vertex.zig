const Self = @This();
const Map = @import("../map.zig");
const Vertex = @import("../vertex.zig");

x: f32,
y: f32,

pub fn init(x: f32, y: f32) Self {
    return .{ .x = x, .y = y };
}

pub fn fromVertex(vertex: Vertex) Self {
    return Self.init(vertex.x, vertex.y);
}

pub fn toVertex(self: Self) Vertex {
    return Vertex.init(self.x, self.y);
}

pub fn createVertexFromMap(map: Map, index: usize) Vertex {
    const vertex = map.vertices.items[index];

    return Vertex.init(vertex.x, vertex.y);
}

pub fn eql(a: Self, b: Self) bool {
    return a.x == b.x and a.y == b.y;
}

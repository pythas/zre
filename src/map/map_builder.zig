const std = @import("std");
const MapVertex = @import("map_vertex.zig");
const MapLine = @import("map_line.zig");
const MapSide = @import("map_side.zig");
const MapSector = @import("map_sector.zig");
const MapEntity = @import("map_entity.zig");
const MapEntityKind = MapEntity.MapEntityKind;
const Vector2 = @import("../vector2.zig");

pub const Edge = struct {
    const Self = @This();

    a: usize,
    b: usize,

    pub fn init(a: usize, b: usize) Self {
        return .{
            .a = a,
            .b = b,
        };
    }

    pub fn fromMapLine(line: MapLine) Self {
        return .{
            .a = line.start,
            .b = line.end,
        };
    }
};

const ComplementedEdge = struct {
    edge: Edge,
    angle: f32,
};

const Wedge = struct {
    vertices: [3]usize,
    used: bool = false,
};

const Region = struct {
    wedges: std.ArrayList(Wedge),
};

pub const Result = struct {
    vertices: std.ArrayList(MapVertex),
    lines: std.ArrayList(MapLine),
    sectors: std.ArrayList(MapSector),
};

pub fn buildMap(allocator: std.mem.Allocator, vertices: []MapVertex, edges: []Edge) !Result {
    var directed_edges = std.ArrayList(ComplementedEdge).init(allocator);
    defer directed_edges.deinit();

    for (edges) |edge| {
        try directed_edges.append(.{ .edge = Edge.init(edge.a, edge.b), .angle = calcAngle(vertices[edge.a], vertices[edge.b]) });
        try directed_edges.append(.{ .edge = Edge.init(edge.b, edge.a), .angle = calcAngle(vertices[edge.b], vertices[edge.a]) });
    }

    const sorted_edges = try directed_edges.toOwnedSlice();
    std.mem.sort(ComplementedEdge, sorted_edges, {}, cmpAngle);

    var wedges = std.ArrayList(Wedge).init(allocator);
    defer wedges.deinit();

    var group = std.ArrayList(ComplementedEdge).init(allocator);
    defer group.deinit();

    // group wedges
    var current_vertex: usize = undefined;

    for (sorted_edges) |sorted_edge| {
        if (sorted_edge.edge.a != current_vertex) {
            current_vertex = sorted_edge.edge.a;

            if (group.items.len > 0) {
                for (0..group.items.len - 1) |i| {
                    const item = group.items[i];
                    const next_item = group.items[i + 1];

                    try wedges.append(.{ .vertices = .{ next_item.edge.b, item.edge.a, item.edge.b } });
                }

                try wedges.append(.{ .vertices = .{ group.items[0].edge.b, group.items[group.items.len - 1].edge.a, group.items[group.items.len - 1].edge.b } });
                try group.resize(0);
            }
        }

        try group.append(sorted_edge);
    }

    if (group.items.len > 0) {
        for (0..group.items.len - 1) |i| {
            const item = group.items[i];
            const next_item = group.items[i + 1];

            try wedges.append(.{ .vertices = .{ next_item.edge.b, item.edge.a, item.edge.b } });
        }

        try wedges.append(.{ .vertices = .{ group.items[0].edge.b, group.items[group.items.len - 1].edge.a, group.items[group.items.len - 1].edge.b } });
        try group.resize(0);
    }

    // sort wedges
    const sorted_wedges = try wedges.toOwnedSlice();
    std.mem.sort(Wedge, sorted_wedges, {}, cmpWedge);

    var regions = std.ArrayList(Region).init(allocator);
    defer regions.deinit();

    // find regions
    while (true) {
        var w1: ?*Wedge = null;

        // get next unused wedge
        for (sorted_wedges) |*sorted_wedge| {
            if (!sorted_wedge.used) {
                w1 = sorted_wedge;
                break;
            }
        }

        // no wedge found, we're done
        if (w1 == null) {
            break;
        }

        w1.?.used = true;

        var current_region = std.ArrayList(Wedge).init(allocator);
        defer current_region.deinit();

        try current_region.append(w1.?.*);

        while (true) {
            // get wedge that matches the last two vertices of the current region
            const wi = current_region.items[current_region.items.len - 1];
            const key: [2]usize = .{ wi.vertices[1], wi.vertices[2] };
            const wi_plus_1_index = std.sort.binarySearch(Wedge, sorted_wedges, key, searchWedge);

            if (wi_plus_1_index == null) {
                break;
            }

            const wi_plus_1 = &sorted_wedges[wi_plus_1_index.?];

            if (wi_plus_1.used) {
                break;
            }

            wi_plus_1.used = true;

            try current_region.append(wi_plus_1.*);

            // it's continous, we're done
            if (isContinous(w1.?.*, wi_plus_1.*)) {
                try regions.append(.{ .wedges = try current_region.clone() });
                break;
            }
        }
    }

    // create sectors from regions
    var sector_lines = std.ArrayList(std.ArrayList(MapLine)).init(allocator);
    defer sector_lines.deinit();

    for (regions.items) |region| {
        var lines = std.ArrayList(MapLine).init(allocator);
        defer lines.deinit();

        for (region.wedges.items) |wedge| {
            try lines.append(.{ .start = wedge.vertices[1], .end = wedge.vertices[2] });
        }

        try sector_lines.append(try lines.clone());
    }

    std.debug.print("sectors: {d}\n", .{sector_lines.items.len});

    var sectors = std.ArrayList(MapSector).init(allocator);
    defer sectors.deinit();

    // filter sectors based on winding order
    var inner_lines = std.ArrayList(MapLine).init(allocator);
    defer inner_lines.deinit();

    var sector_index: usize = 0;

    for (sector_lines.items) |lines| {
        var sum: f32 = 0;

        for (lines.items) |line| {
            const vertex_a = vertices[line.start];
            const vertex_b = vertices[line.end];

            sum += (vertex_b.x - vertex_a.x) * (vertex_b.y + vertex_a.y);
        }

        if (sum != 0) {
            if (sum > 0) {
                for (lines.items) |*line| {
                    std.mem.swap(usize, &line.start, &line.end);
                }
            }

            for (lines.items) |line| {
                // determine the sides of the line
                var found = false;
                for (inner_lines.items) |*test_inner_line| {
                    if ((test_inner_line.start == line.start and test_inner_line.end == line.end) or
                        (test_inner_line.start == line.end and test_inner_line.end == line.start))
                    {
                        if (test_inner_line.side_a == null) {
                            test_inner_line.side_a = .{ .sector = sector_index };
                        } else {
                            test_inner_line.side_b = .{ .sector = sector_index };
                        }
                        found = true;
                    }
                }

                if (!found) {
                    try inner_lines.append(.{
                        .start = line.start,
                        .end = line.end,
                        .side_a = .{ .sector = sector_index },
                    });
                }
            }

            try sectors.append(.{
                .floor_height = -15,
                .ceiling_height = 10,
            });

            sector_index += 1;
        }
    }

    return .{
        .vertices = std.ArrayList(MapVertex).fromOwnedSlice(allocator, vertices),
        .lines = try inner_lines.clone(),
        .sectors = try sectors.clone(),
    };
}

fn isContinous(a: Wedge, b: Wedge) bool {
    return a.vertices[0] == b.vertices[1] and
        a.vertices[1] == b.vertices[2];
}

fn searchWedge(key: [2]usize, mid_item: Wedge) std.math.Order {
    const target_v2 = key[0];
    const target_v3 = key[1];

    if (target_v2 < mid_item.vertices[0]) {
        return std.math.Order.lt;
    } else if (target_v2 > mid_item.vertices[0]) {
        return std.math.Order.gt;
    } else {
        if (target_v3 < mid_item.vertices[1]) {
            return std.math.Order.lt;
        } else if (target_v3 > mid_item.vertices[1]) {
            return std.math.Order.gt;
        } else {
            return std.math.Order.eq;
        }
    }
}

fn cmpAngle(context: void, a: ComplementedEdge, b: ComplementedEdge) bool {
    _ = context;

    if (a.edge.a < b.edge.a) {
        return true;
    } else if (a.edge.a > b.edge.a) {
        return false;
    }

    return a.angle < b.angle;
}

// TODO: array list context...
fn cmpWedge(context: void, a: Wedge, b: Wedge) bool {
    _ = context;

    if (a.vertices[0] < b.vertices[0]) {
        return true;
    } else if (a.vertices[0] > b.vertices[0]) {
        return false;
    }

    return a.vertices[1] < b.vertices[1];
}

fn calcAngle(a: MapVertex, b: MapVertex) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;

    var angle = std.math.atan2(dy, dx);

    if (angle < 0) {
        angle += 2 * std.math.pi;
    }

    return angle;
}

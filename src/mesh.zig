const std = @import("std");
const zmesh = @import("zmesh");
const zgpu = @import("zgpu");
const Animation = @import("animation.zig").Animation;
const loadAnimationsFromGltf = @import("animation.zig").loadAnimationsFromGltf;

pub const Mesh = struct {
    const Self = @This();

    indices: std.ArrayList(u32),
    positions: std.ArrayList([3]f32),
    normals: std.ArrayList([3]f32),
    animations: []Animation,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Self) void {
        self.indices.deinit();
        self.positions.deinit();
        self.normals.deinit();
        for (self.animations) |*anim| {
            anim.deinit();
        }
        self.allocator.free(self.animations);
    }

    pub fn getVertexCount(self: *const Self) usize {
        return self.positions.items.len;
    }

    pub fn getIndexCount(self: *const Self) usize {
        return self.indices.items.len;
    }

    pub fn getAnimation(self: *const Self, name: []const u8) ?*const Animation {
        for (self.animations) |*anim| {
            if (std.mem.eql(u8, anim.name, name)) {
                return anim;
            }
        }
        return null;
    }

    pub fn getAnimationByIndex(self: *const Self, index: usize) ?*const Animation {
        if (index >= self.animations.len) return null;
        return &self.animations[index];
    }

    pub fn initFromPath(allocator: std.mem.Allocator, path: []const u8) !Self {
        var zpath = try allocator.allocSentinel(u8, path.len, 0);
        defer allocator.free(zpath);

        @memcpy(zpath[0..path.len], path);

        zmesh.init(allocator);
        defer zmesh.deinit();

        const data = try zmesh.io.zcgltf.parseAndLoadFile(zpath);
        defer zmesh.io.freeData(data);

        var indices = std.ArrayList(u32).init(allocator);
        var positions = std.ArrayList([3]f32).init(allocator);
        var normals = std.ArrayList([3]f32).init(allocator);

        try zmesh.io.zcgltf.appendMeshPrimitive(
            data,
            0,
            0,
            &indices,
            &positions,
            &normals,
            null,
            null,
        );

        const animations = try loadAnimationsFromGltf(allocator, data);

        return .{
            .indices = indices,
            .positions = positions,
            .normals = normals,
            .animations = animations,
            .allocator = allocator,
        };
    }
};

const Self = @This();
const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");

const TextureRenderer = @import("../texture_renderer.zig");

gctx: *zgpu.GraphicsContext,

pub fn init(allocator: std.mem.Allocator, gctx: *zgpu.GraphicsContext) !*Self {
    const state = try allocator.create(Self);
    state.* = .{
        .gctx = gctx,
    };

    return state;
}

pub fn update(_: *Self) !void {
    // var frame = try Frame.init(std.heap.page_allocator);
    // defer frame.deinit();
}

pub fn getWindowOffset(self: Self) [2]f32 {
    return .{
        self.menu_ui.window_size[0] + self.toolbar_ui.window_size[0],
        self.menu_ui.window_size[1] + self.toolbar_ui.window_size[1],
    };
}

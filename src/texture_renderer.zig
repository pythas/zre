const Self = @This();
const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const TextureBuffer = @import("texture_buffer.zig");

texture: zgpu.TextureHandle,
texture_view: zgpu.TextureViewHandle,
texture_buffer: TextureBuffer,

pub fn init(
    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    comptime width: usize,
    comptime height: usize,
    comptime bit_depth: usize,
) !Self {
    const texture = gctx.createTexture(.{
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
        },
        .size = .{
            .width = width,
            .height = height,
            .depth_or_array_layers = 1,
        },
        .format = .rgba8_unorm,
        .mip_level_count = 1,
    });
    const texture_view = gctx.createTextureView(texture, .{});
    const texture_buffer = try TextureBuffer.init(allocator, width, height, bit_depth);

    return .{
        .texture = texture,
        .texture_view = texture_view,
        .texture_buffer = texture_buffer,
    };
}

pub fn deinit(self: Self) void {
    self.texture_buffer.deinit();
}

pub fn render(self: *Self, gctx: *zgpu.GraphicsContext) void {
    gctx.queue.writeTexture(
        .{ .texture = gctx.lookupResource(self.texture).? },
        .{
            .bytes_per_row = self.texture_buffer.width * 4,
            .rows_per_image = self.texture_buffer.height,
        },
        .{
            .width = self.texture_buffer.width,
            .height = self.texture_buffer.height,
        },
        u8,
        self.texture_buffer.data,
    );
}

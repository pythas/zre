const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const TextureBuffer = @import("texture_buffer.zig").TextureBuffer;
const color = @import("color.zig");

pub const StreamingTexture = struct {
    const Self = @This();

    gctx: *zgpu.GraphicsContext,
    allocator: std.mem.Allocator,
    texture_buffer: TextureBuffer,
    width: u32,
    height: u32,
    texture: zgpu.TextureHandle,
    texture_view: zgpu.TextureViewHandle,
    sampler: zgpu.SamplerHandle,
    bind_group: zgpu.BindGroupHandle,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        bind_group_layout: zgpu.BindGroupLayoutHandle,
        uniforms_buffer: zgpu.BufferHandle,
        w: u32,
        h: u32,
    ) !Self {
        var texture_buffer = try TextureBuffer.init(allocator, w, h, 4);
        texture_buffer.clear(color.getColor(.Black));

        const texture = gctx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{ .width = w, .height = h, .depth_or_array_layers = 1 },
            .format = wgpu.TextureFormat.rgba8_unorm,
            .mip_level_count = 1,
        });
        const texture_view = gctx.createTextureView(texture, .{});
        const sampler = gctx.createSampler(.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
            .mipmap_filter = .nearest,
        });

        const bind_group = gctx.createBindGroup(bind_group_layout, &.{
            .{ .binding = 0, .buffer_handle = uniforms_buffer, .offset = 0, .size = 256 },
            .{ .binding = 1, .texture_view_handle = texture_view },
            .{ .binding = 2, .sampler_handle = sampler },
        });

        return .{
            .gctx = gctx,
            .allocator = allocator,
            .texture_buffer = texture_buffer,
            .width = w,
            .height = h,
            .texture = texture,
            .texture_view = texture_view,
            .sampler = sampler,
            .bind_group = bind_group,
        };
    }

    pub fn deinit(self: *Self) void {
        self.gctx.releaseResource(self.bind_group);
        self.gctx.releaseResource(self.sampler);
        self.gctx.releaseResource(self.texture_view);
        self.gctx.releaseResource(self.texture);
        self.texture_buffer.deinit();
        self.* = undefined;
    }

    pub fn upload(self: *Self) void {
        const bytes_per_row: u32 = self.width * 4;

        self.gctx.queue.writeTexture(
            .{ .texture = self.gctx.lookupResource(self.texture).? },
            .{ .bytes_per_row = bytes_per_row, .rows_per_image = self.height },
            .{ .width = self.width, .height = self.height },
            u8,
            self.texture_buffer.data,
        );
    }

    pub fn resize(
        self: *Self,
        bind_group_layout: zgpu.BindGroupLayoutHandle,
        uniforms_buffer: zgpu.BufferHandle,
        new_w: u32,
        new_h: u32,
    ) !void {
        if (new_w == 0 or new_h == 0) return;

        // Remove old texture buffer
        self.gctx.releaseResource(self.bind_group);
        self.gctx.releaseResource(self.texture_view);
        self.gctx.releaseResource(self.texture);
        self.texture_buffer.deinit();

        // Rebuild texture buffer
        self.texture_buffer = try TextureBuffer.init(self.allocator, new_w, new_h, 4);
        self.texture_buffer.clear(color.getColor(.Black));

        self.width = new_w;
        self.height = new_h;

        self.texture = self.gctx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{ .width = new_w, .height = new_h, .depth_or_array_layers = 1 },
            .format = wgpu.TextureFormat.rgba8_unorm,
            .mip_level_count = 1,
        });
        self.texture_view = self.gctx.createTextureView(self.texture, .{});

        self.bind_group = self.gctx.createBindGroup(bind_group_layout, &.{
            .{ .binding = 0, .buffer_handle = uniforms_buffer, .offset = 0, .size = 256 },
            .{ .binding = 1, .texture_view_handle = self.texture_view },
            .{ .binding = 2, .sampler_handle = self.sampler },
        });
    }
};

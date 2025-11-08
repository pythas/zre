const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const Map = @import("map.zig").Map;
const Light = @import("light.zig").Light;

pub const Uniforms = extern struct {
    screen_wh: [4]f32, // w,h
    player_pos: [4]f32, // x,y
    player_dir: [4]f32, // x,y
    camera_plane: [4]f32, // x,y
    map_size: [4]f32, // w,h
    fog_enabled: [4]f32, // bool
    fog_color: [4]f32, // r,g,b,a
    fog_density: [4]f32, // density
    ceiling_tex: u32,
    floor_tex: u32,
    dt: f32,
    t: f32,
};

const GPULight = extern struct {
    const Self = @This();

    kind: u32, // 0 point, 1 dir
    flags: u32, // bit0 enabled, bit1 shadows
    _pad: [2]u32, // keep 16B alignment
    pos_dir: [4]f32, // xyz pos/dir, w unused
    color_I: [4]f32, // rgb + intensity
    attenuation: [4]f32, // x type (0/1 as float), y linear, z quadratic, w radius

    pub fn fromLight(light: Light) Self {
        return switch (light) {
            .point => |p| .{
                .kind = 0,
                .flags = (@as(u32, @intFromBool(p.enabled)) & 1) |
                    ((@as(u32, @intFromBool(p.casts_shadows)) & 1) << 1),
                ._pad = .{ 0, 0 },
                .pos_dir = .{ p.position.x, p.position.y, p.position.z, 0.0 },
                .color_I = .{ p.color[0], p.color[1], p.color[2], p.intensity },
                .attenuation = switch (p.attenuation) {
                    .quadratic => |a| .{ 0.0, a.linear, a.quadratic, 0.0 },
                    .radial => |a| .{ 1.0, 0.0, 0.0, a.radius },
                },
            },
            .directional => |d| .{
                .kind = 1,
                .flags = (@as(u32, @intFromBool(d.enabled)) & 1) |
                    ((@as(u32, @intFromBool(d.casts_shadows)) & 1) << 1),
                ._pad = .{ 0, 0 },
                .pos_dir = .{ d.direction.x, d.direction.y, d.direction.z, 0.0 },
                .color_I = .{ d.color[0], d.color[1], d.color[2], d.intensity },
                .attenuation = .{ 0.0, 0.0, 0.0, 0.0 },
            },
        };
    }
};

const GPULightBuffer = extern struct {
    count: u32,
    _pad: [3]u32,
    lights: [8]GPULight,
};

pub const WorldRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    window: *zglfw.Window,
    bind_group_layout: zgpu.BindGroupLayoutHandle,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    uniforms_buffer: zgpu.BufferHandle,
    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,
    tilemap: zgpu.TextureHandle,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        map: *const Map,
    ) !Self {
        const bind_group_layout = gctx.createBindGroupLayout(&.{
            zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            zgpu.textureEntry(1, .{ .fragment = true }, .uint, .tvdim_2d, false),
            zgpu.textureEntry(2, .{ .fragment = true }, .float, .tvdim_2d_array, false),
            zgpu.samplerEntry(3, .{ .fragment = true }, .filtering),
            zgpu.bufferEntry(4, .{ .fragment = true }, .read_only_storage, false, 0),
        });
        const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});

        const sampler = gctx.createSampler(.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
            .mipmap_filter = .nearest,
        });

        const map_width: u32 = @intCast(map.width);
        const map_height: u32 = @intCast(map.height);

        // tilemap
        const tilemap = gctx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{
                .width = map_width,
                .height = map_height,
                .depth_or_array_layers = 1,
            },
            .format = wgpu.TextureFormat.r8_uint,
            .mip_level_count = 1,
        });
        const tilemap_view = gctx.createTextureView(tilemap, .{});

        // atlas
        const atlas = gctx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{
                .width = 64,
                .height = 64,
                .depth_or_array_layers = @intCast(map.textures.items.len),
            },
            .format = wgpu.TextureFormat.rgba8_unorm,
            .mip_level_count = 1,
        });
        const atlas_view = gctx.createTextureView(atlas, .{});

        const texture_size = 64 * 64 * 4;

        var textures = try allocator.alloc(u8, map.textures.items.len * texture_size);
        defer allocator.free(textures);

        for (map.textures.items, 0..) |texture, i| {
            const offset = i * texture_size;
            @memcpy(textures[offset .. offset + texture_size], texture.data);
        }

        gctx.queue.writeTexture(
            .{
                .texture = gctx.lookupResource(atlas).?,
                .mip_level = 0,
                .origin = .{ .x = 0, .y = 0, .z = 0 },
            },
            .{
                .bytes_per_row = 64 * 4,
                .rows_per_image = 64,
            },
            .{
                .width = 64,
                .height = 64,
                .depth_or_array_layers = @intCast(map.textures.items.len),
            },
            u8,
            textures,
        );

        // buffers
        const uniforms_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = 256,
        });

        const light_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .storage = true },
            .size = 2048,
        });

        const bind_group = gctx.createBindGroup(bind_group_layout, &.{
            .{ .binding = 0, .buffer_handle = uniforms_buffer, .offset = 0, .size = 256 },
            .{ .binding = 1, .texture_view_handle = tilemap_view },
            .{ .binding = 2, .texture_view_handle = atlas_view },
            .{ .binding = 3, .sampler_handle = sampler },
            .{ .binding = 4, .buffer_handle = light_buffer, .offset = 0, .size = 2048 },
        });

        const pipeline = try createWorldPipeline(
            gctx,
            pipeline_layout,
        );

        // lights
        const num_lights = map.lighting.lights.items.len;
        var gpu_lights: [8]GPULight = undefined;

        for (map.lighting.lights.items, 0..) |light, i| {
            gpu_lights[i] = GPULight.fromLight(light);
        }

        const gpu_light_buffer = GPULightBuffer{
            .count = @intCast(num_lights),
            ._pad = .{ 0, 0, 0 },
            .lights = gpu_lights,
        };

        gctx.queue.writeBuffer(
            gctx.lookupResource(light_buffer).?,
            0,
            u8,
            std.mem.asBytes(&gpu_light_buffer),
        );

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .window = window,
            .bind_group_layout = bind_group_layout,
            .pipeline_layout = pipeline_layout,
            .uniforms_buffer = uniforms_buffer,
            .pipeline = pipeline,
            .bind_group = bind_group,
            .tilemap = tilemap,
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }

    pub fn writeBuffers(self: Self, world: *const World, dt: f32, t: f32) void {
        const wh = self.window.getFramebufferSize();
        const fog = world.map.render_settings.fog;

        var uniforms_data = Uniforms{
            .screen_wh = .{ @floatFromInt(wh[0]), @floatFromInt(wh[1]), 0, 0 },
            .player_pos = .{ world.player.position.x, world.player.position.y, 0, 0 },
            .player_dir = .{ world.player.direction.x, world.player.direction.y, 0, 0 },
            .camera_plane = .{ world.camera.plane.x, world.camera.plane.y, 0, 0 },
            .map_size = .{ @floatFromInt(world.map.width), @floatFromInt(world.map.height), 0, 0 },
            .fog_enabled = .{ if (fog.enabled) 1.0 else 0.0, 0, 0, 0 },
            .fog_color = .{ fog.color[0], fog.color[1], fog.color[2], 1.0 },
            .fog_density = .{ fog.density, 0, 0, 0 },
            .ceiling_tex = @intCast(world.map.ceiling),
            .floor_tex = @intCast(world.map.floor),
            .dt = dt,
            .t = t,
        };

        self.gctx.queue.writeBuffer(
            self.gctx.lookupResource(self.uniforms_buffer).?,
            0,
            u8,
            std.mem.asBytes(&uniforms_data),
        );
    }

    pub fn writeTextures(self: Self, world: *const World) !void {
        const map_width: u32 = @intCast(world.map.width);
        const map_height: u32 = @intCast(world.map.height);

        const map_data = try self.allocator.alloc(u8, map_width * map_height);
        defer self.allocator.free(map_data);

        for (0..world.map.height) |y| {
            for (0..world.map.width) |x| {
                const tile = world.map.getTile(@intCast(x), @intCast(y));
                const id = @as(u8, @intFromEnum(tile.kind)) << 4 | @as(u8, tile.texture);
                map_data[(y * world.map.width) + x] = id;
            }
        }

        self.gctx.queue.writeTexture(
            .{ .texture = self.gctx.lookupResource(self.tilemap).? },
            .{ .bytes_per_row = map_width, .rows_per_image = map_height },
            .{ .width = map_width, .height = map_height },
            u8,
            map_data,
        );
    }
};

pub const Renderer = struct {
    const Self = @This();

    world_renderer: WorldRenderer,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        map: *const Map,
    ) !Self {
        return .{
            .world_renderer = try WorldRenderer.init(
                allocator,
                gctx,
                window,
                map,
            ),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.world_renderer.deinit(allocator);
    }
};

fn createWorldPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("shaders/world_vertex.wgsl"),
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("shaders/world_fragment.wgsl"),
        "fs_main",
    );
    defer fs_module.release();

    const color_targets = [_]wgpu.ColorTargetState{
        .{ .format = gctx.swapchain_descriptor.format },
    };

    const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = 0,
            .buffers = null,
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .none,
        },
        .fragment = &wgpu.FragmentState{
            .module = fs_module,
            .entry_point = "main",
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
    };

    return gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
}

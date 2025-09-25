const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");

pub const Renderer = struct {
    const Self = @This();

    gctx: *zgpu.GraphicsContext,
    bind_group_layout: zgpu.BindGroupLayoutHandle,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    uniforms_buffer: zgpu.BufferHandle,
    pipeline: zgpu.RenderPipelineHandle,

    pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !Self {
        const gctx = try zgpu.GraphicsContext.create(
            allocator,
            .{
                .window = window,
                .fn_getTime = @ptrCast(&zglfw.getTime),
                .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
                .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
                .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
                .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
                .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
                .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
                .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
            },
            .{},
        );

        const bind_group_layout = gctx.createBindGroupLayout(&.{
            zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            zgpu.textureEntry(1, .{ .fragment = true }, .float, .tvdim_2d, false),
            zgpu.samplerEntry(2, .{ .fragment = true }, .filtering),
        });

        const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});

        const uniforms_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = 256,
        });

        const pipeline = try createRenderPipeline(gctx, pipeline_layout);

        return .{
            .gctx = gctx,
            .bind_group_layout = bind_group_layout,
            .pipeline_layout = pipeline_layout,
            .uniforms_buffer = uniforms_buffer,
            .pipeline = pipeline,
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        self.gctx.destroy(allocator);
    }
};

fn createRenderPipeline(gctx: *zgpu.GraphicsContext, pipeline_layout: zgpu.PipelineLayoutHandle) !zgpu.RenderPipelineHandle {
    const vs_module = zgpu.createWgslShaderModule(gctx.device,
        \\struct VertexOutput {
        \\    @builtin(position) position: vec4<f32>,
        \\    @location(0) tex_coords: vec2<f32>,
        \\}
        \\
        \\@vertex fn main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
        \\    // Create a fullscreen quad as two triangles
        \\    var positions = array<vec2<f32>, 6>(
        \\        vec2<f32>(-1.0, -1.0),
        \\        vec2<f32>(1.0, -1.0),
        \\        vec2<f32>(-1.0, 1.0),
        \\        vec2<f32>(-1.0, 1.0),
        \\        vec2<f32>(1.0, -1.0),
        \\        vec2<f32>(1.0, 1.0),
        \\    );
        \\
        \\    // UV coordinates (0,0 is top-left, 1,1 is bottom-right)
        \\    var tex_coords = array<vec2<f32>, 6>(
        \\        vec2<f32>(0.0, 1.0),
        \\        vec2<f32>(1.0, 1.0),
        \\        vec2<f32>(0.0, 0.0),
        \\        vec2<f32>(0.0, 0.0),
        \\        vec2<f32>(1.0, 1.0),
        \\        vec2<f32>(1.0, 0.0),
        \\    );
        \\
        \\    var output: VertexOutput;
        \\    output.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
        \\    output.tex_coords = tex_coords[vertex_index];
        \\    return output;
        \\}
    , "vs_main");
    defer vs_module.release();

    const fs_module = zgpu.createWgslShaderModule(gctx.device,
        \\struct Uniforms {
        \\    data: array<vec4<f32>, 16>, // Using vec4 instead of f32 for proper alignment
        \\}
        \\
        \\@group(0) @binding(0) var<uniform> uniforms: Uniforms;
        \\@group(0) @binding(1) var texture: texture_2d<f32>;
        \\@group(0) @binding(2) var texture_sampler: sampler;
        \\
        \\@fragment fn main(@location(0) tex_coords: vec2<f32>) -> @location(0) vec4<f32> {
        \\    return textureSample(texture, texture_sampler, tex_coords);
        \\}
    , "fs_main");
    defer fs_module.release();

    const color_targets = [_]wgpu.ColorTargetState{.{
        .format = gctx.swapchain_descriptor.format,
    }};

    const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = 0,
            .buffers = null,
        },
        .primitive = wgpu.PrimitiveState{
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

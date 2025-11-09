const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const StreamingTexture = @import("../streaming_texture.zig").StreamingTexture;
const World = @import("../world.zig").World;
const Map = @import("../map.zig").Map;
const MapResult = @import("../map.zig").MapResult;
const MapSource = @import("../world.zig").MapSource;
const KeyboardState = @import("../world.zig").KeyboardState;
const WorldRenderer = @import("../renderer.zig").WorldRenderer;
const ViewmodelRenderer = @import("../renderer.zig").ViewmodelRenderer;
const Viewmodel = @import("../viewmodel.zig").Viewmodel;
const ViewmodelAction = @import("../viewmodel.zig").ViewmodelAction;

pub const GameMode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    world_renderer: WorldRenderer,
    viewmodel_renderer: ViewmodelRenderer,
    keyboard_state: KeyboardState,
    world: World,
    viewmodel: Viewmodel,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        map_result: *MapResult,
    ) !Self {
        const world = try World.init(allocator, map_result);
        const world_renderer = try WorldRenderer.init(allocator, gctx, window, &world.map);
        var viewmodel = try Viewmodel.init(allocator);
        const viewmodel_renderer = try ViewmodelRenderer.init(allocator, gctx, window, &viewmodel);
        const keyboard_state = KeyboardState.init(window);

        return .{
            .allocator = allocator,
            .world = world,
            .window = window,
            .world_renderer = world_renderer,
            .viewmodel_renderer = viewmodel_renderer,
            .viewmodel = viewmodel,
            .keyboard_state = keyboard_state,
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
        self.world_renderer.deinit(self.allocator);
        self.viewmodel_renderer.deinit(self.allocator);
        self.viewmodel.deinit();
    }

    pub fn update(self: *Self, dt: f32) !void {
        self.keyboard_state.beginFrame();
        self.world.update(dt, &self.keyboard_state, self.window);
        self.viewmodel.update(dt);

        if (self.world.player.attack_anim) |attack| {
            const expected_action = switch (attack.attack_type) {
                .horizontal_slash => ViewmodelAction.horizontal_slash,
                .overhead_strike => ViewmodelAction.overhead_strike,
                .thrust => ViewmodelAction.thrust,
            };

            if (self.viewmodel.current_action != expected_action) {
                self.viewmodel.playAttack(attack.attack_type);
            }
        } else {
            const is_attack_action = self.viewmodel.current_action == .horizontal_slash or
                self.viewmodel.current_action == .overhead_strike or
                self.viewmodel.current_action == .thrust;

            if (is_attack_action and !self.viewmodel.anim_state.is_playing) {
                self.viewmodel.current_action = .idle;
            }
        }
    }

    pub fn render(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        dt: f32,
        t: f32,
    ) !void {
        {
            const renderer = self.world_renderer;
            const gctx = renderer.gctx;

            try renderer.writeTextures(&self.world);
            renderer.writeBuffers(&self.world, dt, t);

            const pipeline = gctx.lookupResource(renderer.pipeline).?;
            const bind_group = gctx.lookupResource(renderer.bind_group).?;

            pass.setPipeline(pipeline);
            pass.setBindGroup(0, bind_group, null);
            pass.draw(3, 1, 0, 0);
        }

        // Render viewmodel
        {
            const renderer = self.viewmodel_renderer;
            const gctx = renderer.gctx;

            try renderer.writeTextures(&self.world);
            renderer.writeBuffers(&self.viewmodel, dt, t);

            const pipeline = gctx.lookupResource(renderer.pipeline).?;
            const bind_group = gctx.lookupResource(renderer.bind_group).?;
            const vertex_buffer = gctx.lookupResourceInfo(renderer.vertex_buffer).?;
            const index_buffer = gctx.lookupResourceInfo(renderer.index_buffer).?;

            const num_indices: u32 = @intCast(self.viewmodel.mesh.getIndexCount());

            pass.setPipeline(pipeline);
            pass.setBindGroup(0, bind_group, null);
            pass.setVertexBuffer(0, vertex_buffer.gpuobj.?, 0, vertex_buffer.size);
            pass.setIndexBuffer(index_buffer.gpuobj.?, .uint32, 0, index_buffer.size);
            pass.drawIndexed(num_indices, 1, 0, 0, 0);
        }

        self.world.map.is_dirty = false;
    }
};

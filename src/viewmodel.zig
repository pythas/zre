const std = @import("std");

const Mesh = @import("mesh.zig").Mesh;
const Animation = @import("animation.zig").Animation;
const AnimationState = @import("animation.zig").AnimationState;

pub const AttackType = enum {
    horizontal_slash,
    overhead_strike,
    thrust,
};

pub const ViewmodelAction = enum {
    idle,
    horizontal_slash,
    overhead_strike,
    thrust,
    reload,
    equip,
};

pub const ViewmodelTransform = struct {
    translation: [3]f32,
    rotation: [4]f32,
    scale: [3]f32,
};

pub const Viewmodel = struct {
    const Self = @This();

    mesh: Mesh,
    anim_state: AnimationState,
    current_action: ViewmodelAction,

    pub fn deinit(self: *Self) void {
        self.mesh.deinit();
    }

    pub fn init(allocator: std.mem.Allocator) !Self {
        const mesh = try Mesh.initFromPath(allocator, "assets/meshes/sword_fixed.gltf");
        var viewmodel = Self{
            .mesh = mesh,
            .anim_state = AnimationState.init(),
            .current_action = .idle,
        };

        if (mesh.animations.len > 0) {
            viewmodel.playAction(.idle);
        }

        return viewmodel;
    }

    pub fn update(self: *Self, dt: f32) void {
        self.anim_state.update(dt);
    }

    pub fn playAction(self: *Self, action: ViewmodelAction) void {
        self.current_action = action;

        const animation = self.getAnimationForAction(action);
        if (animation) |anim| {
            const should_loop = action == .idle;
            self.anim_state.play(anim, should_loop);
        }
    }

    pub fn playAttack(self: *Self, attack_type: AttackType) void {
        const action = switch (attack_type) {
            .horizontal_slash => ViewmodelAction.horizontal_slash,
            .overhead_strike => ViewmodelAction.overhead_strike,
            .thrust => ViewmodelAction.thrust,
        };
        self.playAction(action);
    }

    fn getAnimationForAction(self: *Self, action: ViewmodelAction) ?*const Animation {
        const anim_name = switch (action) {
            .idle => "idle",
            .horizontal_slash => "horizontal_slash",
            .overhead_strike => "overhead_strike",
            .thrust => "thrust",
            .reload => "reload",
            .equip => "equip",
        };

        return self.mesh.getAnimation(anim_name);
    }

    pub fn getCurrentTransform(self: *const Self) ViewmodelTransform {
        var transform = ViewmodelTransform{
            .translation = [3]f32{ 0.0, 0.0, 0.0 },
            .rotation = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
            .scale = [3]f32{ 1.0, 1.0, 1.0 },
        };

        if (self.anim_state.current_animation) |anim| {
            const time = self.anim_state.current_time;

            _ = anim.sample(time, 0, .rotation, &transform.rotation);
            _ = anim.sample(time, 0, .translation, &transform.translation);
        }

        return transform;
    }
};
